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

#ifndef COMETA_WITHDRAWALS_H
#define COMETA_WITHDRAWALS_H

/* REWARD ACCOUNTS ***********************************************************/

/* The pinned reward parser accepts payment headers and extra bytes. Validate
 * identity before it can normalize them; construction and inspection stay native. */
static cardano_error_t
check_reward_bytes(const uint8_t* bytes, size_t size)
{
  if (size != 29 || (bytes[0] >> 4) < 14 || (bytes[0] & 15) > 1)
    return CARDANO_ERROR_INVALID_ADDRESS_FORMAT;
  return CARDANO_SUCCESS;
}

static cardano_error_t
parse_reward(lean_object* bytes, cardano_reward_address_t** result)
{
  cardano_error_t code = check_reward_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (code == CARDANO_SUCCESS)
    code = cardano_reward_address_from_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), result);
  return code;
}

static cardano_error_t
build_reward(lean_object* fields, cardano_reward_address_t** result)
{
  cardano_credential_t* credential = NULL;
  cardano_error_t       code;
  lean_object*          children = FIELD_CHILDREN(fields);
  if (FIELD_KIND(fields) > 1 || lean_is_scalar(children) || !lean_is_scalar(lean_ctor_get(children, 1)))
    return CARDANO_ERROR_INVALID_ARGUMENT;
  TRY(build_credential(lean_ctor_get(children, 0), &credential));
  TRY(cardano_reward_address_from_credentials((cardano_network_id_t)FIELD_KIND(fields), credential, result));
cleanup:
  cardano_credential_unref(&credential);
  return code;
}

static cardano_error_t
read_reward(cardano_reward_address_t* account, lean_object** result)
{
  cardano_credential_t* credential = cardano_reward_address_get_credential(account);
  lean_object*          node       = NULL;
  cardano_network_id_t  network;
  cardano_error_t       code;
  TRY(cardano_reward_address_get_network_id(account, &network));
  TRY(read_credential(credential, &node));
  *result = component_node(network, 0, copy_bytes(cardano_reward_address_get_bytes(account), cardano_reward_address_get_bytes_size(account)), copy_bytes(NULL, 0), lean_mk_string(""), component_cons(node, lean_box(0)));
cleanup:
  cardano_credential_unref(&credential);
  return code;
}

/* WITHDRAWAL MAPS ***********************************************************/

/* Consume a map with the native reader, validating raw address keys before the
 * native map parser can normalize them. Native getters expose duplicate keys;
 * the public Lean snapshot validator rejects those without coalescing amounts. */
static cardano_error_t
check_withdrawal_keys(cardano_cbor_reader_t* reader)
{
  cardano_buffer_t*           bytes = NULL;
  cardano_cbor_reader_state_t state;
  cardano_error_t             code;
  int64_t                     length;
  TRY(cardano_cbor_reader_read_start_map(reader, &length));
  for (;;)
  {
    TRY(cardano_cbor_reader_peek_state(reader, &state));
    if (state == CARDANO_CBOR_READER_STATE_END_MAP)
      break;
    TRY(cardano_cbor_reader_read_bytestring(reader, &bytes));
    TRY(check_reward_bytes(cardano_buffer_get_data(bytes), cardano_buffer_get_size(bytes)));
    cardano_buffer_unref(&bytes);
    bytes = NULL;
    TRY(cardano_cbor_reader_skip_value(reader));
  }
  TRY(cardano_cbor_reader_read_end_map(reader));
cleanup:
  cardano_buffer_unref(&bytes);
  return code;
}

static cardano_error_t
parse_withdrawals(lean_object* bytes, cardano_withdrawal_map_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code;
  TRY(check_withdrawal_keys(reader));
  TRY(require_end(reader));
  cardano_cbor_reader_unref(&reader);
  reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }
  TRY(cardano_withdrawal_map_from_cbor(reader, result));
  TRY(require_end(reader));
cleanup:
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_withdrawals(cardano_withdrawal_map_t* map, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_withdrawal_map_to_cbor(map, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
build_withdrawals(lean_object* fields, cardano_withdrawal_map_t** result)
{
  cardano_withdrawal_map_t* map     = NULL;
  cardano_reward_address_t* account = NULL;
  cardano_error_t           code;
  TRY(cardano_withdrawal_map_new(&map));
  for (lean_object* list = FIELD_CHILDREN(fields); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    lean_object* entry = lean_ctor_get(list, 0);
    TRY(parse_reward(FIELD_BYTES(entry), &account));
    TRY(cardano_withdrawal_map_insert(map, account, FIELD_NUMBER(entry)));
    cardano_reward_address_unref(&account);
    account = NULL;
  }
  *result = map;
  map     = NULL;
cleanup:
  cardano_reward_address_unref(&account);
  cardano_withdrawal_map_unref(&map);
  return code;
}

static cardano_error_t
read_withdrawals(cardano_withdrawal_map_t* map, lean_object** result)
{
  cardano_reward_address_t* account = NULL;
  lean_object*              entries = lean_box(0);
  cardano_error_t           code    = CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_withdrawal_map_get_length(map); ++i)
  {
    uint64_t amount;
    TRY(cardano_withdrawal_map_get_key_value_at(map, i, &account, &amount));
    entries = component_cons(component_leaf(0, amount, copy_bytes(cardano_reward_address_get_bytes(account), cardano_reward_address_get_bytes_size(account))), entries);
    cardano_reward_address_unref(&account);
    account = NULL;
  }
  *result = component_node(0, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(entries));
  entries = lean_box(0);
cleanup:
  lean_dec(entries);
  cardano_reward_address_unref(&account);
  return code;
}

#endif
