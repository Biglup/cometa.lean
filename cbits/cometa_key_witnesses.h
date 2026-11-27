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

#ifndef COMETA_KEY_WITNESSES_H
#define COMETA_KEY_WITNESSES_H

/* VERIFICATION-KEY WITNESSES ************************************************/

static cardano_error_t
parse_vkey_witness(lean_object* bytes, cardano_vkey_witness_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_vkey_witness_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_vkey_witness(cardano_vkey_witness_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_vkey_witness_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
build_vkey_witness(lean_object* fields, cardano_vkey_witness_t** result)
{
  cardano_ed25519_public_key_t* key       = NULL;
  cardano_ed25519_signature_t*  signature = NULL;
  cardano_error_t               code;
  TRY(cardano_ed25519_public_key_from_bytes(lean_sarray_cptr(FIELD_BYTES(fields)), lean_sarray_size(FIELD_BYTES(fields)), &key));
  TRY(cardano_ed25519_signature_from_bytes(lean_sarray_cptr(FIELD_EXTRA(fields)), lean_sarray_size(FIELD_EXTRA(fields)), &signature));
  TRY(cardano_vkey_witness_new(key, signature, result));
cleanup:
  cardano_ed25519_public_key_unref(&key);
  cardano_ed25519_signature_unref(&signature);
  return code;
}

static cardano_error_t
read_vkey_witness(cardano_vkey_witness_t* value, lean_object** result)
{
  cardano_ed25519_public_key_t* key       = cardano_vkey_witness_get_vkey(value);
  cardano_ed25519_signature_t*  signature = cardano_vkey_witness_get_signature(value);
  cardano_blake2b_hash_t*       hash      = NULL;
  cardano_error_t               code;
  if (key == NULL || signature == NULL)
  {
    code = CARDANO_ERROR_POINTER_IS_NULL;
    goto cleanup;
  }
  TRY(cardano_ed25519_public_key_to_hash(key, &hash));
  *result = component_node(0, 0, copy_bytes(cardano_ed25519_public_key_get_data(key), cardano_ed25519_public_key_get_bytes_size(key)), copy_bytes(cardano_ed25519_signature_get_data(signature), cardano_ed25519_signature_get_bytes_size(signature)), lean_mk_string(""), component_cons(component_leaf(0, 0, copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash))), lean_box(0)));
cleanup:
  cardano_blake2b_hash_unref(&hash);
  cardano_ed25519_public_key_unref(&key);
  cardano_ed25519_signature_unref(&signature);
  return code;
}

/* The pinned collection reader does not release a child if that child's reader
 * fails after allocating it (for example, an invalid indefinite-array ending).
 * Preflight with the same native child reader, always releasing the out-pointer.
 * This is not an alternate witness codec. */
static cardano_error_t
check_vkey_set_reader(cardano_cbor_reader_t* reader)
{
  cardano_vkey_witness_t*     witness = NULL;
  cardano_cbor_reader_state_t state;
  cardano_error_t             code;
  int64_t                     length;
  TRY(cardano_cbor_reader_peek_state(reader, &state));
  if (state == CARDANO_CBOR_READER_STATE_TAG)
  {
    cardano_cbor_tag_t tag;
    TRY(cardano_cbor_reader_read_tag(reader, &tag));
    if (tag != CARDANO_CBOR_TAG_SET)
    {
      code = CARDANO_ERROR_INVALID_CBOR_VALUE;
      goto cleanup;
    }
  }
  TRY(cardano_cbor_reader_read_start_array(reader, &length));
  for (;;)
  {
    TRY(cardano_cbor_reader_peek_state(reader, &state));
    if (state == CARDANO_CBOR_READER_STATE_END_ARRAY)
      break;
    TRY(cardano_vkey_witness_from_cbor(reader, &witness));
    cardano_vkey_witness_unref(&witness);
    witness = NULL;
  }
  TRY(cardano_cbor_reader_read_end_array(reader));
cleanup:
  cardano_vkey_witness_unref(&witness);
  return code;
}

/* Apply the same child guard before every native full-transaction parse. Other
 * witness fields are skipped by the native reader and decoded by cardano-c. */
static cardano_error_t
check_transaction_key_witnesses(lean_object* bytes)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_cbor_reader_state_t state;
  cardano_error_t             code;
  int64_t                     length;
  TRY(cardano_cbor_reader_read_start_array(reader, &length));
  TRY(cardano_cbor_reader_skip_value(reader));
  TRY(cardano_cbor_reader_read_start_map(reader, &length));
  for (;;)
  {
    TRY(cardano_cbor_reader_peek_state(reader, &state));
    if (state == CARDANO_CBOR_READER_STATE_END_MAP)
      break;
    uint64_t key;
    TRY(cardano_cbor_reader_read_uint(reader, &key));
    if (key == 0)
      TRY(check_vkey_set_reader(reader));
    else
      TRY(cardano_cbor_reader_skip_value(reader));
  }
cleanup:
  cardano_cbor_reader_unref(&reader);
  return code;
}

/* COLLECTION CODECS *********************************************************/

static cardano_error_t
parse_vkey_set(lean_object* bytes, cardano_vkey_witness_set_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code;
  TRY(check_vkey_set_reader(reader));
  TRY(require_end(reader));
  cardano_cbor_reader_unref(&reader);
  reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }
  TRY(cardano_vkey_witness_set_from_cbor(reader, result));
  TRY(require_end(reader));
cleanup:
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_vkey_set(cardano_vkey_witness_set_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_vkey_witness_set_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
build_vkey_set(lean_object* fields, cardano_vkey_witness_set_t** result)
{
  cardano_vkey_witness_set_t* collection = NULL;
  cardano_vkey_witness_t*     witness    = NULL;
  cardano_error_t             code;
  TRY(cardano_vkey_witness_set_new(&collection));
  TRY(cardano_vkey_witness_set_set_use_tag(collection, FIELD_KIND(fields) != 0));
  for (lean_object* items = FIELD_CHILDREN(fields); !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(parse_vkey_witness(FIELD_BYTES(lean_ctor_get(items, 0)), &witness));
    TRY(cardano_vkey_witness_set_add(collection, witness));
    cardano_vkey_witness_unref(&witness);
    witness = NULL;
  }
  *result    = collection;
  collection = NULL;
cleanup:
  cardano_vkey_witness_unref(&witness);
  cardano_vkey_witness_set_unref(&collection);
  return code;
}

static cardano_error_t
read_vkey_set(cardano_vkey_witness_set_t* collection, lean_object** result)
{
  cardano_vkey_witness_t* witness  = NULL;
  lean_object*            children = lean_box(0);
  lean_object*            bytes    = NULL;
  cardano_error_t         code     = CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_vkey_witness_set_get_length(collection); ++i)
  {
    TRY(cardano_vkey_witness_set_get(collection, i, &witness));
    TRY(serialize_vkey_witness(witness, &bytes));
    children = component_cons(component_leaf(0, 0, bytes), children);
    bytes    = NULL;
    cardano_vkey_witness_unref(&witness);
    witness = NULL;
  }
  *result  = component_node(cardano_vkey_witness_set_get_use_tag(collection) ? 1 : 0, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children));
  children = lean_box(0);
cleanup:
  if (bytes != NULL)
    lean_dec(bytes);
  lean_dec(children);
  cardano_vkey_witness_unref(&witness);
  return code;
}

/* NATIVE SIGNATURE VERIFICATION *********************************************/

LEAN_EXPORT lean_obj_res
cometa_lean_vkey_verify(b_lean_obj_arg bytes, b_lean_obj_arg message)
{
  cardano_vkey_witness_t*       witness   = NULL;
  cardano_ed25519_public_key_t* key       = NULL;
  cardano_ed25519_signature_t*  signature = NULL;
  bool                          valid     = false;
  cardano_error_t               code;
  TRY(parse_vkey_witness(bytes, &witness));
  key       = cardano_vkey_witness_get_vkey(witness);
  signature = cardano_vkey_witness_get_signature(witness);
  if (key == NULL || signature == NULL)
  {
    code = CARDANO_ERROR_POINTER_IS_NULL;
    goto cleanup;
  }
  valid = cardano_ed25519_public_verify(key, signature, lean_sarray_cptr(message), lean_sarray_size(message));
cleanup:
  cardano_ed25519_public_key_unref(&key);
  cardano_ed25519_signature_unref(&signature);
  cardano_vkey_witness_unref(&witness);
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(lean_box(valid));
  return native_error(code);
}

/* TRANSACTION MERGING *******************************************************/

static cardano_error_t
parse_witness_transaction(lean_object* bytes, cardano_transaction_t** result)
{
  cardano_error_t code = check_transaction_key_witnesses(bytes);
  if (code != CARDANO_SUCCESS)
    return code;
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  code = cardano_transaction_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

LEAN_EXPORT lean_obj_res
cometa_lean_transaction_vkeys(b_lean_obj_arg bytes)
{
  cardano_transaction_t*      transaction = NULL;
  cardano_witness_set_t*      witnesses   = NULL;
  cardano_vkey_witness_set_t* collection  = NULL;
  lean_object*                result      = NULL;
  cardano_error_t             code;
  TRY(parse_witness_transaction(bytes, &transaction));
  witnesses  = cardano_transaction_get_witness_set(transaction);
  collection = cardano_witness_set_get_vkeys(witnesses);
  if (collection == NULL)
    result = copy_bytes(NULL, 0);
  else
    TRY(serialize_vkey_set(collection, &result));
cleanup:
  cardano_vkey_witness_set_unref(&collection);
  cardano_witness_set_unref(&witnesses);
  cardano_transaction_unref(&transaction);
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(result);
  if (result != NULL)
    lean_dec(result);
  return native_error(code);
}

/* Temporarily detach only the key collection from this call-local native object.
 * Keep an owned reference and restore it even on serialization failure. This lets
 * the native writer compare every other witness field before and after merging. */
static cardano_error_t
serialize_other_witnesses(cardano_witness_set_t* witnesses, lean_object** result)
{
  cardano_vkey_witness_set_t* keys   = cardano_witness_set_get_vkeys(witnesses);
  cardano_cbor_writer_t*      writer = NULL;
  cardano_error_t             code;
  TRY(cardano_witness_set_set_vkeys(witnesses, NULL));
  writer = cardano_cbor_writer_new();
  if (writer == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }
  TRY(cardano_witness_set_to_cbor(witnesses, writer));
  TRY(component_writer_bytes(writer, result));
cleanup:
{
  cardano_error_t restored = cardano_witness_set_set_vkeys(witnesses, keys);
  if (code == CARDANO_SUCCESS)
    code = restored;
}
  cardano_cbor_writer_unref(&writer);
  cardano_vkey_witness_set_unref(&keys);
  return code;
}

static cardano_error_t
snapshot_preserved_fields(cardano_transaction_t* transaction, lean_object** body_bytes, lean_object** auxiliary_bytes, lean_object** other_witnesses)
{
  cardano_transaction_body_t* body      = cardano_transaction_get_body(transaction);
  cardano_auxiliary_data_t*   auxiliary = cardano_transaction_get_auxiliary_data(transaction);
  cardano_witness_set_t*      witnesses = cardano_transaction_get_witness_set(transaction);
  cardano_error_t             code;
  TRY(serialize_body(body, body_bytes));
  if (auxiliary == NULL)
    *auxiliary_bytes = copy_bytes(NULL, 0);
  else
    TRY(serialize_auxiliary(auxiliary, auxiliary_bytes));
  TRY(serialize_other_witnesses(witnesses, other_witnesses));
cleanup:
  cardano_transaction_body_unref(&body);
  cardano_auxiliary_data_unref(&auxiliary);
  cardano_witness_set_unref(&witnesses);
  return code;
}

static bool
same_witness_bytes(lean_object* left, lean_object* right)
{
  size_t size = lean_sarray_size(left);
  return size == lean_sarray_size(right) && (size == 0 || memcmp(lean_sarray_cptr(left), lean_sarray_cptr(right), size) == 0);
}

/* Borrow both encodings; the native apply function performs the actual merge.
 * No clear_cbor_cache call is permitted here: it would change signed identities. */
LEAN_EXPORT lean_obj_res
cometa_lean_transaction_apply_vkeys(b_lean_obj_arg bytes, b_lean_obj_arg additions)
{
  cardano_transaction_t*      transaction = NULL;
  cardano_witness_set_t*      witnesses   = NULL;
  cardano_vkey_witness_set_t* incoming    = NULL;
  cardano_vkey_witness_set_t* current     = NULL;
  cardano_cbor_writer_t*      writer      = NULL;
  lean_object*                before[3]   = { NULL, NULL, NULL };
  lean_object*                after[3]    = { NULL, NULL, NULL };
  lean_object*                result      = NULL;
  cardano_error_t             code;
  TRY(parse_witness_transaction(bytes, &transaction));
  TRY(parse_vkey_set(additions, &incoming));
  TRY(snapshot_preserved_fields(transaction, &before[0], &before[1], &before[2]));
  bool validity = cardano_transaction_get_is_valid(transaction);
  witnesses     = cardano_transaction_get_witness_set(transaction);
  current       = cardano_witness_set_get_vkeys(witnesses);
  if (current == NULL)
  {
    TRY(cardano_vkey_witness_set_new(&current));
    TRY(cardano_vkey_witness_set_set_use_tag(current, cardano_vkey_witness_set_get_use_tag(incoming)));
    TRY(cardano_witness_set_set_vkeys(witnesses, current));
  }
  TRY(cardano_transaction_apply_vkey_witnesses(transaction, incoming));
  TRY(snapshot_preserved_fields(transaction, &after[0], &after[1], &after[2]));
  if (validity != cardano_transaction_get_is_valid(transaction) || !same_witness_bytes(before[0], after[0]) || !same_witness_bytes(before[1], after[1]) || !same_witness_bytes(before[2], after[2]))
  {
    code = CARDANO_ERROR_INVALID_ARGUMENT;
    goto cleanup;
  }
  writer = cardano_cbor_writer_new();
  if (writer == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }
  TRY(cardano_transaction_to_cbor(transaction, writer));
  TRY(component_writer_bytes(writer, &result));
cleanup:
  for (size_t i = 0; i < 3; ++i)
  {
    if (before[i] != NULL)
      lean_dec(before[i]);
    if (after[i] != NULL)
      lean_dec(after[i]);
  }
  cardano_cbor_writer_unref(&writer);
  cardano_vkey_witness_set_unref(&current);
  cardano_vkey_witness_set_unref(&incoming);
  cardano_witness_set_unref(&witnesses);
  cardano_transaction_unref(&transaction);
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(result);
  if (result != NULL)
    lean_dec(result);
  return native_error(code);
}

#endif
