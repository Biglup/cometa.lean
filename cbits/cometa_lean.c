/*
 * Copyright 2026 Biglup Labs
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* INCLUDES ******************************************************************/

#include <cardano/cardano.h>
#include <lean/lean.h>
#include <string.h>

/* DEFINITIONS ***************************************************************/

/**
 * Return the original native error code as the EIO UInt32 error payload.
 * This intentionally does not construct an IO.Error.
 */
static lean_obj_res
native_error(cardano_error_t code)
{
  return lean_io_result_mk_error(lean_box_uint32((uint32_t)code));
}

/**
 * Consume one native address reference, copying both borrowed buffers into Lean.
 * The returned pair and all its fields are owned by the EIO result. Even when
 * parsing fails, release any non-null reference supplied by the native parser.
 */
static lean_obj_res
address_result(cardano_error_t code, cardano_address_t* address)
{
  if (code != CARDANO_SUCCESS || address == NULL)
  {
    cardano_address_unref(&address);
    return native_error(code == CARDANO_SUCCESS ? CARDANO_ERROR_INVALID_ADDRESS_FORMAT : code);
  }

  const size_t size  = cardano_address_get_bytes_size(address);
  lean_object* bytes = lean_alloc_sarray(1, size, size);
  memcpy(lean_sarray_cptr(bytes), cardano_address_get_bytes(address), size);
  lean_object* text = lean_mk_string(cardano_address_get_string(address));
  cardano_address_unref(&address);

  lean_object* pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, bytes);
  lean_ctor_set(pair, 1, text);
  return lean_io_result_mk_ok(pair);
}

/** Parse borrowed text. Lean 4.36 erases the world argument at this boundary. */
LEAN_EXPORT lean_obj_res
cometa_lean_address_from_text(b_lean_obj_arg text)
{
  cardano_address_t*    address = NULL;
  const cardano_error_t code    = cardano_address_from_string(
    lean_string_cstr(text), lean_string_size(text) - 1, &address);
  return address_result(code, address);
}

/** Parse borrowed bytes; the returned snapshot never aliases native storage. */
LEAN_EXPORT lean_obj_res
cometa_lean_address_from_bytes(b_lean_obj_arg bytes)
{
  cardano_address_t*    address = NULL;
  const cardano_error_t code    = cardano_address_from_bytes(
    lean_sarray_cptr(bytes), lean_sarray_size(bytes), &address);
  return address_result(code, address);
}

/** Copy the native static version string into an owned Lean string. */
LEAN_EXPORT lean_obj_res
cometa_lean_native_version(void)
{
  return lean_mk_string(cardano_get_lib_version());
}

/* TRANSACTION SNAPSHOTS *****************************************************/

/** Copy a borrowed buffer; the new byte array owns its storage. */
static lean_obj_res
copy_bytes(const byte_t* data, size_t size)
{
  lean_object* bytes = lean_alloc_sarray(1, size, size);
  if (size != 0)
  {
    memcpy(lean_sarray_cptr(bytes), data, size);
  }
  return bytes;
}

/** Consume both fields into a boxed Lean Prod. Scalars must already be boxed. */
static lean_obj_res
owned_pair(lean_obj_arg first, lean_obj_arg second)
{
  lean_object* result = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(result, 0, first);
  lean_ctor_set(result, 1, second);
  return result;
}

/**
 * Borrow the input set; get() and get_id() each acquire a native reference.
 * Always return an owned Lean array through result, even on a partial failure.
 * The caller releases that array on failure, including all completed elements.
 */
static cardano_error_t
snapshot_inputs(cardano_transaction_input_set_t* inputs, lean_object** result)
{
  const size_t count = cardano_transaction_input_set_get_length(inputs);
  *result            = lean_alloc_array(0, count);

  for (size_t index = 0; index < count; ++index)
  {
    cardano_transaction_input_t* input = NULL;
    cardano_blake2b_hash_t*      hash  = NULL;
    cardano_error_t              code  = cardano_transaction_input_set_get(inputs, index, &input);

    if (code == CARDANO_SUCCESS)
    {
      hash = cardano_transaction_input_get_id(input);
      if (hash == NULL)
      {
        code = CARDANO_ERROR_POINTER_IS_NULL;
      }
      else
      {
        lean_object* identifier   = copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash));
        lean_object* output_index = lean_box_uint64(cardano_transaction_input_get_index(input));
        *result                   = lean_array_push(*result, owned_pair(identifier, output_index));
      }
    }

    cardano_blake2b_hash_unref(&hash);
    cardano_transaction_input_unref(&input);
    if (code != CARDANO_SUCCESS)
    {
      return code;
    }
  }
  return CARDANO_SUCCESS;
}

/** Borrow an output; return owned serialized bytes, or NULL on failure. */
static cardano_error_t
encode_output(cardano_transaction_output_t* output, lean_object** result)
{
  *result                       = NULL;
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
  {
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  }

  cardano_error_t code = cardano_transaction_output_to_cbor(output, writer);
  if (code == CARDANO_SUCCESS)
  {
    const size_t size  = cardano_cbor_writer_get_encode_size(writer);
    lean_object* bytes = lean_alloc_sarray(1, size, size);
    code               = cardano_cbor_writer_encode(writer, lean_sarray_cptr(bytes), size);
    if (code == CARDANO_SUCCESS)
    {
      *result = bytes;
    }
    else
    {
      lean_dec(bytes);
    }
  }
  cardano_cbor_writer_unref(&writer);
  return code;
}

/**
 * Borrow an output and copy its address, coin, and native-reserialized CBOR.
 * Getters acquire address/value references, which are released on all paths.
 * On failure result is NULL and no Lean allocation escapes.
 */
static cardano_error_t
snapshot_output(cardano_transaction_output_t* output, lean_object** result)
{
  *result                    = NULL;
  cardano_address_t* address = cardano_transaction_output_get_address(output);
  cardano_value_t*   value   = cardano_transaction_output_get_value(output);
  lean_object*       cbor    = NULL;
  cardano_error_t    code    = CARDANO_ERROR_POINTER_IS_NULL;

  if (address != NULL && value != NULL)
  {
    code = encode_output(output, &cbor);
    if (code == CARDANO_SUCCESS)
    {
      lean_object* bytes = copy_bytes(cardano_address_get_bytes(address), cardano_address_get_bytes_size(address));
      /* Restore the unsigned coin representation used by the native CBOR writer. */
      lean_object* coin = lean_box_uint64((uint64_t)cardano_value_get_coin(value));
      *result           = owned_pair(bytes, owned_pair(coin, cbor));
    }
  }

  cardano_value_unref(&value);
  cardano_address_unref(&address);
  return code;
}

/** Borrow the output list; return an owned, possibly partial Lean array. */
static cardano_error_t
snapshot_outputs(cardano_transaction_output_list_t* outputs, lean_object** result)
{
  const size_t count = cardano_transaction_output_list_get_length(outputs);
  *result            = lean_alloc_array(0, count);

  for (size_t index = 0; index < count; ++index)
  {
    cardano_transaction_output_t* output   = NULL;
    lean_object*                  snapshot = NULL;
    cardano_error_t               code     = cardano_transaction_output_list_get(outputs, index, &output);
    if (code == CARDANO_SUCCESS)
    {
      code = snapshot_output(output, &snapshot);
    }
    cardano_transaction_output_unref(&output);
    if (code != CARDANO_SUCCESS)
    {
      return code;
    }
    *result = lean_array_push(*result, snapshot);
  }
  return CARDANO_SUCCESS;
}

/**
 * Borrow one CBOR byte array. Lean 4.36 erases the world argument. Return EIO
 * UInt32 RawTransaction: nested boxed products, with copied bytes/owned arrays.
 * The reader, transaction, body, hash, and collections each own a reference;
 * every path releases them. No native object or borrowed buffer reaches Lean.
 */
LEAN_EXPORT lean_obj_res
cometa_lean_transaction_from_cbor(b_lean_obj_arg bytes)
{
  cardano_cbor_reader_t*             reader       = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  cardano_transaction_t*             transaction  = NULL;
  cardano_transaction_body_t*        body         = NULL;
  cardano_blake2b_hash_t*            hash         = NULL;
  cardano_transaction_input_set_t*   inputs       = NULL;
  cardano_transaction_output_list_t* outputs      = NULL;
  lean_object*                       lean_inputs  = NULL;
  lean_object*                       lean_outputs = NULL;
  lean_object*                       result       = NULL;
  cardano_error_t                    code         = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  size_t                             remaining    = 0;

  if (reader == NULL)
  {
    goto cleanup;
  }

  code = cardano_transaction_from_cbor(reader, &transaction);
  if (code != CARDANO_SUCCESS)
  {
    goto cleanup;
  }
  code = cardano_cbor_reader_get_bytes_remaining(reader, &remaining);
  if (code != CARDANO_SUCCESS)
  {
    goto cleanup;
  }
  if (remaining != 0)
  {
    code = CARDANO_ERROR_INVALID_CBOR_VALUE;
    goto cleanup;
  }

  body    = cardano_transaction_get_body(transaction);
  hash    = cardano_transaction_get_id(transaction);
  inputs  = cardano_transaction_body_get_inputs(body);
  outputs = cardano_transaction_body_get_outputs(body);
  if (body == NULL || hash == NULL || inputs == NULL || outputs == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }

  code = snapshot_inputs(inputs, &lean_inputs);
  if (code != CARDANO_SUCCESS)
  {
    goto cleanup;
  }
  code = snapshot_outputs(outputs, &lean_outputs);
  if (code != CARDANO_SUCCESS)
  {
    goto cleanup;
  }

  lean_object* identifier = copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash));
  lean_object* fee        = lean_box_uint64(cardano_transaction_body_get_fee(body));
  lean_object* validity   = lean_box(cardano_transaction_get_is_valid(transaction));
  lean_object* snapshot   = owned_pair(lean_inputs, lean_outputs);
  snapshot                = owned_pair(validity, snapshot);
  snapshot                = owned_pair(fee, snapshot);
  result                  = lean_io_result_mk_ok(owned_pair(identifier, snapshot));
  lean_inputs             = NULL;
  lean_outputs            = NULL;

cleanup:
  if (lean_inputs != NULL)
  {
    lean_dec(lean_inputs);
  }
  if (lean_outputs != NULL)
  {
    lean_dec(lean_outputs);
  }
  cardano_transaction_output_list_unref(&outputs);
  cardano_transaction_input_set_unref(&inputs);
  cardano_blake2b_hash_unref(&hash);
  cardano_transaction_body_unref(&body);
  cardano_transaction_unref(&transaction);
  cardano_cbor_reader_unref(&reader);
  return result != NULL ? result : native_error(code);
}

/* OUTPUT, DATUM, AND SCRIPT CODECS *******************************************/

/** Require complete byte consumption without disclosing input contents. */
static cardano_error_t
require_end(cardano_cbor_reader_t* reader)
{
  size_t          remaining = 0;
  cardano_error_t code      = cardano_cbor_reader_get_bytes_remaining(reader, &remaining);
  return code != CARDANO_SUCCESS ? code : remaining == 0 ? CARDANO_SUCCESS
                                                         : CARDANO_ERROR_INVALID_CBOR_VALUE;
}

/** Consume an owned native hash reference; copy its borrowed bytes into Lean. */
static lean_obj_res
hash_result(cardano_error_t code, cardano_blake2b_hash_t* hash)
{
  if (code != CARDANO_SUCCESS || hash == NULL)
  {
    cardano_blake2b_hash_unref(&hash);
    return native_error(code == CARDANO_SUCCESS ? CARDANO_ERROR_MEMORY_ALLOCATION_FAILED : code);
  }
  lean_object* bytes = copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash));
  cardano_blake2b_hash_unref(&hash);
  return lean_io_result_mk_ok(bytes);
}

/** Borrow exact datum CBOR; release parser/data references and return its hash. */
LEAN_EXPORT lean_obj_res
cometa_lean_datum_hash(b_lean_obj_arg bytes)
{
  cardano_cbor_reader_t*  reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  cardano_plutus_data_t*  data   = NULL;
  cardano_blake2b_hash_t* hash   = NULL;
  cardano_error_t         code   = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  if (reader != NULL)
  {
    code = cardano_plutus_data_from_cbor(reader, &data);
    if (code == CARDANO_SUCCESS)
    {
      code = require_end(reader);
    }
    if (code == CARDANO_SUCCESS)
    {
      code = cardano_blake2b_compute_hash(lean_sarray_cptr(bytes), lean_sarray_size(bytes), 32, &hash);
    }
  }
  cardano_plutus_data_unref(&data);
  cardano_cbor_reader_unref(&reader);
  return hash_result(code, hash);
}

/** Borrow a script envelope; native hashing includes its language discriminator. */
LEAN_EXPORT lean_obj_res
cometa_lean_script_hash(b_lean_obj_arg bytes)
{
  cardano_cbor_reader_t*  reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  cardano_script_t*       script = NULL;
  cardano_blake2b_hash_t* hash   = NULL;
  cardano_error_t         code   = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  if (reader != NULL)
  {
    code = cardano_script_from_cbor(reader, &script);
    if (code == CARDANO_SUCCESS)
    {
      code = require_end(reader);
    }
    if (code == CARDANO_SUCCESS)
    {
      hash = cardano_script_get_hash(script);
    }
  }
  cardano_script_unref(&script);
  cardano_cbor_reader_unref(&reader);
  return hash_result(code, hash);
}

/** Borrow one output's CBOR; native references never escape the call. */
LEAN_EXPORT lean_obj_res
cometa_lean_output_round_trip(b_lean_obj_arg bytes)
{
  cardano_cbor_reader_t*        reader  = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  cardano_transaction_output_t* output  = NULL;
  lean_object*                  encoded = NULL;
  cardano_error_t               code    = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  if (reader != NULL)
  {
    code = cardano_transaction_output_from_cbor(reader, &output);
    if (code == CARDANO_SUCCESS)
    {
      code = require_end(reader);
    }
    if (code == CARDANO_SUCCESS)
    {
      code = encode_output(output, &encoded);
    }
  }
  cardano_transaction_output_unref(&output);
  cardano_cbor_reader_unref(&reader);
  return code == CARDANO_SUCCESS ? lean_io_result_mk_ok(encoded) : native_error(code);
}
