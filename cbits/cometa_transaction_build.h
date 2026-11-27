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

#ifndef COMETA_TRANSACTION_BUILD_H
#define COMETA_TRANSACTION_BUILD_H

/* INPUTS AND RESOLVED OUTPUTS ***********************************************/

/* Included after component helpers. Every getter returns an acquired reference;
 * reset released locals because native unref may leave retained pointers intact. */
static cardano_error_t
build_input(lean_object* fields, cardano_transaction_input_t** result)
{
  cardano_blake2b_hash_t* hash  = NULL;
  lean_object*            bytes = FIELD_BYTES(fields);
  cardano_error_t         code  = cardano_blake2b_hash_from_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), &hash);
  if (code == CARDANO_SUCCESS)
    code = cardano_transaction_input_new(hash, FIELD_NUMBER(fields), result);
  cardano_blake2b_hash_unref(&hash);
  return code;
}

static cardano_error_t
read_input(cardano_transaction_input_t* input, lean_object** result)
{
  cardano_blake2b_hash_t* hash = cardano_transaction_input_get_id(input);
  if (hash == NULL)
    return CARDANO_ERROR_POINTER_IS_NULL;
  *result = component_leaf(0, cardano_transaction_input_get_index(input), copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash)));
  cardano_blake2b_hash_unref(&hash);
  return CARDANO_SUCCESS;
}

static cardano_error_t
build_input_set(lean_object* fields, cardano_transaction_input_set_t** result)
{
  cardano_transaction_input_set_t* inputs = NULL;
  cardano_transaction_input_t*     input  = NULL;
  cardano_error_t                  code;
  TRY(cardano_transaction_input_set_new(&inputs));
  for (lean_object* list = FIELD_CHILDREN(fields); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    TRY(build_input(lean_ctor_get(list, 0), &input));
    TRY(cardano_transaction_input_set_add(inputs, input));
    cardano_transaction_input_unref(&input);
    input = NULL;
  }
  *result = inputs;
  inputs  = NULL;
cleanup:
  cardano_transaction_input_unref(&input);
  cardano_transaction_input_set_unref(&inputs);
  return code;
}

static cardano_error_t
read_input_set(cardano_transaction_input_set_t* inputs, lean_object** result)
{
  lean_object*                 children = lean_box(0);
  lean_object*                 snapshot = NULL;
  cardano_transaction_input_t* input    = NULL;
  cardano_error_t              code     = CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_transaction_input_set_get_length(inputs); ++i)
  {
    TRY(cardano_transaction_input_set_get(inputs, i, &input));
    TRY(read_input(input, &snapshot));
    children = component_cons(snapshot, children);
    snapshot = NULL;
    cardano_transaction_input_unref(&input);
    input = NULL;
  }
  *result  = component_node(0, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children));
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_transaction_input_unref(&input);
  return code;
}

static cardano_error_t
build_utxo(lean_object* fields, cardano_utxo_t** result)
{
  cardano_transaction_input_t*  input  = NULL;
  cardano_transaction_output_t* output = NULL;
  cardano_error_t               code;
  lean_object*                  children = FIELD_CHILDREN(fields);
  if (lean_is_scalar(children))
    return CARDANO_ERROR_INVALID_ARGUMENT;
  TRY(build_input(lean_ctor_get(children, 0), &input));
  TRY(parse_output(FIELD_BYTES(fields), &output));
  TRY(cardano_utxo_new(input, output, result));
cleanup:
  cardano_transaction_input_unref(&input);
  cardano_transaction_output_unref(&output);
  return code;
}

static cardano_error_t
read_utxo(cardano_utxo_t* utxo, lean_object** result)
{
  cardano_transaction_input_t*  input     = cardano_utxo_get_input(utxo);
  cardano_transaction_output_t* output    = cardano_utxo_get_output(utxo);
  lean_object*                  reference = NULL;
  lean_object*                  bytes     = NULL;
  cardano_error_t               code      = CARDANO_ERROR_POINTER_IS_NULL;
  if (input == NULL || output == NULL)
    goto cleanup;
  TRY(read_input(input, &reference));
  TRY(serialize_output(output, &bytes));
  *result   = component_node(0, 0, bytes, copy_bytes(NULL, 0), lean_mk_string(""), component_cons(reference, lean_box(0)));
  reference = bytes = NULL;
cleanup:
  if (reference != NULL)
    lean_dec(reference);
  if (bytes != NULL)
    lean_dec(bytes);
  cardano_transaction_input_unref(&input);
  cardano_transaction_output_unref(&output);
  return code;
}

/* Preflight nested output fields with the native reader before invoking native
 * parent parsers. This extends the existing duplicate-output-key leak guard to
 * UTxOs and bodies without decoding or replacing any field codec. */
static cardano_error_t
check_encoded_output(cardano_cbor_reader_t* reader)
{
  cardano_buffer_t* buffer = NULL;
  cardano_error_t   code   = cardano_cbor_reader_read_encoded_value(reader, &buffer);
  if (code == CARDANO_SUCCESS)
  {
    lean_object* bytes = copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer));
    code               = check_output_keys(bytes);
    lean_dec(bytes);
  }
  cardano_buffer_unref(&buffer);
  return code;
}

static cardano_error_t
check_utxo_output(lean_object* bytes)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code;
  int64_t         length;
  TRY(cardano_cbor_reader_read_start_array(reader, &length));
  TRY(cardano_cbor_reader_skip_value(reader));
  TRY(check_encoded_output(reader));
cleanup:
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
check_body_outputs(lean_object* bytes)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t             code;
  cardano_cbor_reader_state_t state;
  int64_t                     length;
  TRY(cardano_cbor_reader_read_start_map(reader, &length));
  for (;;)
  {
    TRY(cardano_cbor_reader_peek_state(reader, &state));
    if (state == CARDANO_CBOR_READER_STATE_END_MAP)
      break;
    uint64_t key;
    TRY(cardano_cbor_reader_read_uint(reader, &key));
    if (key == 1)
    {
      TRY(cardano_cbor_reader_read_start_array(reader, &length));
      for (;;)
      {
        TRY(cardano_cbor_reader_peek_state(reader, &state));
        if (state == CARDANO_CBOR_READER_STATE_END_ARRAY)
          break;
        TRY(check_encoded_output(reader));
      }
      TRY(cardano_cbor_reader_read_end_array(reader));
    }
    else if (key == 16)
      TRY(check_encoded_output(reader));
    else
      TRY(cardano_cbor_reader_skip_value(reader));
  }
cleanup:
  cardano_cbor_reader_unref(&reader);
  return code;
}

/* NATIVE CODECS *************************************************************/

static cardano_error_t
parse_input(lean_object* bytes, cardano_transaction_input_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_input_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_input(cardano_transaction_input_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_input_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
parse_input_set(lean_object* bytes, cardano_transaction_input_set_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_input_set_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_input_set(cardano_transaction_input_set_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_input_set_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
parse_utxo(lean_object* bytes, cardano_utxo_t** result)
{
  cardano_error_t checked = check_utxo_output(bytes);
  if (checked != CARDANO_SUCCESS)
    return checked;
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_utxo_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_utxo(cardano_utxo_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_utxo_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
parse_body(lean_object* bytes, cardano_transaction_body_t** result)
{
  cardano_error_t checked = check_body_outputs(bytes);
  if (checked != CARDANO_SUCCESS)
    return checked;
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_body_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_body(cardano_transaction_body_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_body_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

/* EXPLICIT BODY CONSTRUCTION ***********************************************/

/* Transport tags select native setters/getters. They are not a CBOR encoder. */
static lean_object*
body_field(lean_object* fields, uint64_t kind)
{
  for (lean_object* list = FIELD_CHILDREN(fields); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    lean_object* field = lean_ctor_get(list, 0);
    if (FIELD_KIND(field) == kind)
      return field;
  }
  return NULL;
}

static cardano_error_t
build_body(lean_object* fields, cardano_transaction_body_t** result)
{
  cardano_transaction_body_t*        body       = NULL;
  cardano_transaction_input_set_t*   inputs     = NULL;
  cardano_transaction_output_list_t* outputs    = NULL;
  cardano_transaction_output_t*      output     = NULL;
  cardano_multi_asset_t*             mint       = NULL;
  cardano_blake2b_hash_t*            hash       = NULL;
  cardano_guard_set_t*               guards     = NULL;
  cardano_credential_t*              credential = NULL;
  cardano_error_t                    code;
  lean_object*                       input_field  = body_field(fields, 0);
  lean_object*                       output_field = body_field(fields, 1);
  if (input_field == NULL || output_field == NULL)
    return CARDANO_ERROR_INVALID_ARGUMENT;
  TRY(parse_input_set(FIELD_BYTES(input_field), &inputs));
  TRY(cardano_transaction_output_list_new(&outputs));
  for (lean_object* list = FIELD_CHILDREN(output_field); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    TRY(parse_output(FIELD_BYTES(lean_ctor_get(list, 0)), &output));
    TRY(cardano_transaction_output_list_add(outputs, output));
    cardano_transaction_output_unref(&output);
    output = NULL;
  }
  TRY(cardano_transaction_body_new(inputs, outputs, FIELD_NUMBER(fields), NULL, &body));
  cardano_transaction_input_set_unref(&inputs);
  inputs = NULL;
  for (lean_object* list = FIELD_CHILDREN(fields); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    lean_object* field  = lean_ctor_get(list, 0);
    uint64_t     number = FIELD_NUMBER(field);
    lean_object* bytes  = FIELD_BYTES(field);
    switch (FIELD_KIND(field))
    {
      case 0:
      case 1:
        break;
      case 3:
        TRY(cardano_transaction_body_set_invalid_after(body, &number));
        break;
      case 8:
        TRY(cardano_transaction_body_set_invalid_before(body, &number));
        break;
      case 17:
        TRY(cardano_transaction_body_set_total_collateral(body, &number));
        break;
      case 21:
        TRY(cardano_transaction_body_set_treasury_value(body, &number));
        break;
      case 22:
        TRY(cardano_transaction_body_set_donation(body, &number));
        break;
      case 7:
        TRY(cardano_blake2b_hash_from_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), &hash));
        TRY(cardano_transaction_body_set_aux_data_hash(body, hash));
        cardano_blake2b_hash_unref(&hash);
        hash = NULL;
        break;
      case 11:
        TRY(cardano_blake2b_hash_from_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), &hash));
        TRY(cardano_transaction_body_set_script_data_hash(body, hash));
        cardano_blake2b_hash_unref(&hash);
        hash = NULL;
        break;
      case 13:
        TRY(parse_input_set(bytes, &inputs));
        TRY(cardano_transaction_body_set_collateral(body, inputs));
        cardano_transaction_input_set_unref(&inputs);
        inputs = NULL;
        break;
      case 18:
        TRY(parse_input_set(bytes, &inputs));
        TRY(cardano_transaction_body_set_reference_inputs(body, inputs));
        cardano_transaction_input_set_unref(&inputs);
        inputs = NULL;
        break;

      case 9:
        TRY(parse_assets(bytes, &mint));
        TRY(cardano_transaction_body_set_mint(body, mint));
        cardano_multi_asset_unref(&mint);
        mint = NULL;
        break;
      case 14:
        TRY(cardano_guard_set_new(&guards));
        for (lean_object* items = FIELD_CHILDREN(field); !lean_is_scalar(items); items = lean_ctor_get(items, 1))
        {
          TRY(build_credential(lean_ctor_get(items, 0), &credential));
          TRY(cardano_guard_set_add(guards, credential));
          cardano_credential_unref(&credential);
          credential = NULL;
        }
        TRY(cardano_transaction_body_set_guards(body, guards));
        cardano_guard_set_unref(&guards);
        guards = NULL;
        break;
      case 15:
      {
        if (number > 1)
        {
          code = CARDANO_ERROR_INVALID_ARGUMENT;
          goto cleanup;
        }
        cardano_network_id_t network = (cardano_network_id_t)number;
        TRY(cardano_transaction_body_set_network_id(body, &network));
        break;
      }
      case 16:
        TRY(parse_output(bytes, &output));
        TRY(cardano_transaction_body_set_collateral_return(body, output));
        cardano_transaction_output_unref(&output);
        output = NULL;
        break;
      default:
        code = CARDANO_ERROR_INVALID_ARGUMENT;
        goto cleanup;
    }
  }
  *result = body;
  body    = NULL;
cleanup:
  cardano_transaction_body_unref(&body);
  cardano_transaction_input_set_unref(&inputs);
  cardano_transaction_output_list_unref(&outputs);
  cardano_transaction_output_unref(&output);
  cardano_multi_asset_unref(&mint);
  cardano_blake2b_hash_unref(&hash);
  cardano_guard_set_unref(&guards);
  cardano_credential_unref(&credential);
  return code;
}

/* BODY SNAPSHOTS ************************************************************/

static cardano_error_t
read_body(cardano_transaction_body_t* body, lean_object** result)
{
  cardano_error_t                    code       = CARDANO_SUCCESS;
  cardano_transaction_input_set_t*   inputs     = NULL;
  cardano_transaction_output_list_t* outputs    = NULL;
  cardano_transaction_output_t*      output     = NULL;
  cardano_multi_asset_t*             mint       = NULL;
  cardano_blake2b_hash_t*            hash       = NULL;
  cardano_guard_set_t*               guards     = NULL;
  cardano_credential_t*              credential = NULL;
  lean_object*                       children   = lean_box(0);
  lean_object*                       entries    = lean_box(0);
  lean_object*                       bytes      = NULL;
  bool                               additional = false;

  inputs = cardano_transaction_body_get_inputs(body);
  TRY(serialize_input_set(inputs, &bytes));
  children = component_cons(component_leaf(0, 0, bytes), children);
  bytes    = NULL;
  cardano_transaction_input_set_unref(&inputs);
  inputs  = NULL;
  outputs = cardano_transaction_body_get_outputs(body);
  for (size_t i = 0; i < cardano_transaction_output_list_get_length(outputs); ++i)
  {
    TRY(cardano_transaction_output_list_get(outputs, i, &output));
    TRY(serialize_output(output, &bytes));
    entries = component_cons(component_leaf(0, 0, bytes), entries);
    bytes   = NULL;
    cardano_transaction_output_unref(&output);
    output = NULL;
  }
  children                      = component_cons(component_node(1, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(entries)), children);
  entries                       = lean_box(0);
  const uint64_t* invalid_after = cardano_transaction_body_get_invalid_after(body);
  if (invalid_after != NULL)
    children = component_cons(component_leaf(3, *invalid_after, copy_bytes(NULL, 0)), children);
  const uint64_t* invalid_before = cardano_transaction_body_get_invalid_before(body);
  if (invalid_before != NULL)
    children = component_cons(component_leaf(8, *invalid_before, copy_bytes(NULL, 0)), children);
  const uint64_t* total_collateral = cardano_transaction_body_get_total_collateral(body);
  if (total_collateral != NULL)
    children = component_cons(component_leaf(17, *total_collateral, copy_bytes(NULL, 0)), children);
  const uint64_t* treasury_value = cardano_transaction_body_get_treasury_value(body);
  if (treasury_value != NULL)
    children = component_cons(component_leaf(21, *treasury_value, copy_bytes(NULL, 0)), children);
  const uint64_t* donation = cardano_transaction_body_get_donation(body);
  if (donation != NULL)
    children = component_cons(component_leaf(22, *donation, copy_bytes(NULL, 0)), children);
  hash = cardano_transaction_body_get_aux_data_hash(body);
  if (hash != NULL)
  {
    children = component_cons(component_leaf(7, 0, copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash))), children);
    cardano_blake2b_hash_unref(&hash);
    hash = NULL;
  }
  hash = cardano_transaction_body_get_script_data_hash(body);
  if (hash != NULL)
  {
    children = component_cons(component_leaf(11, 0, copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash))), children);
    cardano_blake2b_hash_unref(&hash);
    hash = NULL;
  }
  inputs = cardano_transaction_body_get_collateral(body);
  if (inputs != NULL)
  {
    TRY(serialize_input_set(inputs, &bytes));
    children = component_cons(component_leaf(13, 0, bytes), children);
    bytes    = NULL;
    cardano_transaction_input_set_unref(&inputs);
    inputs = NULL;
  }
  inputs = cardano_transaction_body_get_reference_inputs(body);
  if (inputs != NULL)
  {
    TRY(serialize_input_set(inputs, &bytes));
    children = component_cons(component_leaf(18, 0, bytes), children);
    bytes    = NULL;
    cardano_transaction_input_set_unref(&inputs);
    inputs = NULL;
  }

  mint = cardano_transaction_body_get_mint(body);
  if (mint != NULL)
  {
    TRY(serialize_assets(mint, &bytes));
    children = component_cons(component_leaf(9, 0, bytes), children);
    bytes    = NULL;
  }
  guards = cardano_transaction_body_get_guards(body);
  if (guards != NULL)
  {
    for (size_t i = 0; i < cardano_guard_set_get_length(guards); ++i)
    {
      TRY(cardano_guard_set_get(guards, i, &credential));
      TRY(read_credential(credential, &bytes));
      entries = component_cons(bytes, entries);
      bytes   = NULL;
      cardano_credential_unref(&credential);
      credential = NULL;
    }
    children = component_cons(component_node(14, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(entries)), children);
    entries  = lean_box(0);
  }
  const cardano_network_id_t* network = cardano_transaction_body_get_network_id(body);
  if (network != NULL)
    children = component_cons(component_leaf(15, *network, copy_bytes(NULL, 0)), children);
  output = cardano_transaction_body_get_collateral_return(body);
  if (output != NULL)
  {
    TRY(serialize_output(output, &bytes));
    children = component_cons(component_leaf(16, 0, bytes), children);
    bytes    = NULL;
  }
  {
    cardano_certificate_set_t* value = cardano_transaction_body_get_certificates(body);
    additional                       = additional || value != NULL;
    cardano_certificate_set_unref(&value);
  }
  {
    cardano_withdrawal_map_t* value = cardano_transaction_body_get_withdrawals(body);
    additional                      = additional || value != NULL;
    cardano_withdrawal_map_unref(&value);
  }
  {
    cardano_update_t* value = cardano_transaction_body_get_update(body);
    additional              = additional || value != NULL;
    cardano_update_unref(&value);
  }
  {
    cardano_voting_procedures_t* value = cardano_transaction_body_get_voting_procedures(body);
    additional                         = additional || value != NULL;
    cardano_voting_procedures_unref(&value);
  }
  {
    cardano_proposal_procedure_set_t* value = cardano_transaction_body_get_proposal_procedures(body);
    additional                              = additional || value != NULL;
    cardano_proposal_procedure_set_unref(&value);
  }
  {
    cardano_sub_transaction_set_t* value = cardano_transaction_body_get_sub_transactions(body);
    additional                           = additional || value != NULL;
    cardano_sub_transaction_set_unref(&value);
  }
  {
    cardano_required_guards_map_t* value = cardano_transaction_body_get_required_top_level_guards(body);
    additional                           = additional || value != NULL;
    cardano_required_guards_map_unref(&value);
  }
  {
    cardano_direct_deposit_map_t* value = cardano_transaction_body_get_direct_deposits(body);
    additional                          = additional || value != NULL;
    cardano_direct_deposit_map_unref(&value);
  }
  {
    cardano_account_balance_intervals_map_t* value = cardano_transaction_body_get_account_balance_intervals(body);
    additional                                     = additional || value != NULL;
    cardano_account_balance_intervals_map_unref(&value);
  }
  {
    cardano_account_balance_intervals_map_t* value = cardano_transaction_body_get_starting_account_balance_intervals(body);
    additional                                     = additional || value != NULL;
    cardano_account_balance_intervals_map_unref(&value);
  }

  hash = cardano_transaction_body_get_hash(body);
  if (hash == NULL)
  {
    code = CARDANO_ERROR_POINTER_IS_NULL;
    goto cleanup;
  }
  *result  = component_node(additional ? 1 : 0, cardano_transaction_body_get_fee(body), copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash)), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children));
  children = lean_box(0);
cleanup:
  lean_dec(children);
  lean_dec(entries);
  if (bytes != NULL)
    lean_dec(bytes);
  cardano_transaction_input_set_unref(&inputs);
  cardano_transaction_output_list_unref(&outputs);
  cardano_transaction_output_unref(&output);
  cardano_multi_asset_unref(&mint);
  cardano_blake2b_hash_unref(&hash);
  cardano_guard_set_unref(&guards);
  cardano_credential_unref(&credential);
  return code;
}

/* UNSIGNED TRANSACTION ASSEMBLY *********************************************/

/* Borrow a complete body, retain its native CBOR cache, and construct an empty
 * witness set. Native transaction serialization determines the frame. */
LEAN_EXPORT lean_obj_res
cometa_lean_unsigned_transaction(b_lean_obj_arg body_bytes, uint8_t is_valid)
{
  cardano_transaction_body_t* body        = NULL;
  cardano_witness_set_t*      witnesses   = NULL;
  cardano_transaction_t*      transaction = NULL;
  cardano_cbor_writer_t*      writer      = NULL;
  lean_object*                bytes       = NULL;
  cardano_error_t             code;
  TRY(parse_body(body_bytes, &body));
  TRY(cardano_witness_set_new(&witnesses));
  TRY(cardano_transaction_new(body, witnesses, NULL, &transaction));
  TRY(cardano_transaction_set_is_valid(transaction, is_valid != 0));
  writer = cardano_cbor_writer_new();
  if (writer == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }
  TRY(cardano_transaction_to_cbor(transaction, writer));
  TRY(component_writer_bytes(writer, &bytes));
cleanup:
  cardano_cbor_writer_unref(&writer);
  cardano_transaction_unref(&transaction);
  cardano_witness_set_unref(&witnesses);
  cardano_transaction_body_unref(&body);
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(bytes);
  if (bytes != NULL)
    lean_dec(bytes);
  return native_error(code);
}

#endif
