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

#ifndef COMETA_COMPONENTS_H
#define COMETA_COMPONENTS_H

/* COPIED FIELD TRANSPORT ****************************************************/

/* Included by cometa_lean.c; uses its copying/result helpers. Component.node is
 * audited against Lean 4.36 generated C: four objects (bytes, extra, decimal,
 * children), followed by kind and number as two uint64 scalars. Inputs borrow
 * every field; snapshots own all fields. Native references never escape. */
#define FIELD_BYTES(n)    lean_ctor_get(n, 0)
#define FIELD_EXTRA(n)    lean_ctor_get(n, 1)
#define FIELD_TEXT(n)     lean_ctor_get(n, 2)
#define FIELD_CHILDREN(n) lean_ctor_get(n, 3)
#define FIELD_KIND(n)     lean_ctor_get_uint64(n, sizeof(void*) * 4)
#define FIELD_NUMBER(n)   lean_ctor_get_uint64(n, sizeof(void*) * 4 + 8)
#define TRY(call)                \
  do                             \
  {                              \
    code = (call);               \
    if (code != CARDANO_SUCCESS) \
      goto cleanup;              \
  }                              \
  while (0)

static lean_object*
component_node(uint64_t kind, uint64_t number, lean_object* bytes, lean_object* extra, lean_object* text, lean_object* children)
{
  lean_object* node = lean_alloc_ctor(0, 4, 16);
  lean_ctor_set(node, 0, bytes);
  lean_ctor_set(node, 1, extra);
  lean_ctor_set(node, 2, text);
  lean_ctor_set(node, 3, children);
  lean_ctor_set_uint64(node, sizeof(void*) * 4, kind);
  lean_ctor_set_uint64(node, sizeof(void*) * 4 + 8, number);
  return node;
}

static lean_object*
component_leaf(uint64_t kind, uint64_t number, lean_object* bytes)
{
  return component_node(kind, number, bytes, copy_bytes(NULL, 0), lean_mk_string(""), lean_box(0));
}

/* Cons consumes both owned objects. Reverse consumes the owned list. */
static lean_object*
component_cons(lean_object* item, lean_object* rest)
{
  lean_object* cell = lean_alloc_ctor(1, 2, 0);
  lean_ctor_set(cell, 0, item);
  lean_ctor_set(cell, 1, rest);
  return cell;
}

static lean_object*
component_reverse(lean_object* list)
{
  lean_object* result = lean_box(0);
  while (!lean_is_scalar(list))
  {
    lean_object* item = lean_ctor_get(list, 0);
    lean_object* next = lean_ctor_get(list, 1);
    lean_inc(item);
    lean_inc(next);
    lean_dec(list);
    result = component_cons(item, result);
    list   = next;
  }
  return result;
}

static cardano_error_t
component_writer_bytes(cardano_cbor_writer_t* writer, lean_object** result)
{
  size_t          size  = cardano_cbor_writer_get_encode_size(writer);
  lean_object*    bytes = lean_alloc_sarray(1, size, size);
  cardano_error_t code  = cardano_cbor_writer_encode(writer, lean_sarray_cptr(bytes), size);
  if (code == CARDANO_SUCCESS)
    *result = bytes;
  else
    lean_dec(bytes);
  return code;
}

/* Preserve the native signed quantity bit pattern without implementation-defined
 * unsigned-to-signed conversion. Lean validates the range before construction. */
static int64_t
component_signed(uint64_t bits)
{
  int64_t value;
  memcpy(&value, &bits, sizeof(value));
  return value;
}

/* CREDENTIALS ***************************************************************/

static cardano_error_t
build_credential(lean_object* node, cardano_credential_t** result)
{
  if (FIELD_KIND(node) > 1)
    return CARDANO_ERROR_INVALID_ARGUMENT;
  lean_object* bytes = FIELD_BYTES(node);
  return cardano_credential_from_hash_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), (cardano_credential_type_t)FIELD_KIND(node), result);
}

static cardano_error_t
read_credential(cardano_credential_t* value, lean_object** result)
{
  cardano_credential_type_t kind;
  cardano_error_t           code = cardano_credential_get_type(value, &kind);
  if (code == CARDANO_SUCCESS)
    *result = component_leaf(kind, 0, copy_bytes(cardano_credential_get_hash_bytes(value), cardano_credential_get_hash_bytes_size(value)));
  return code;
}

/* VALUES ********************************************************************/

static cardano_error_t
build_assets(lean_object* node, cardano_multi_asset_t** result)
{
  cardano_multi_asset_t*  assets = NULL;
  cardano_blake2b_hash_t* policy = NULL;
  cardano_asset_name_t*   name   = NULL;
  cardano_error_t         code;
  TRY(cardano_multi_asset_new(&assets));
  for (lean_object* list = FIELD_CHILDREN(node); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    lean_object* item         = lean_ctor_get(list, 0);
    lean_object* policy_bytes = FIELD_BYTES(item);
    lean_object* name_bytes   = FIELD_EXTRA(item);
    TRY(cardano_blake2b_hash_from_bytes(lean_sarray_cptr(policy_bytes), lean_sarray_size(policy_bytes), &policy));
    TRY(cardano_asset_name_from_bytes(lean_sarray_cptr(name_bytes), lean_sarray_size(name_bytes), &name));
    TRY(cardano_multi_asset_set(assets, policy, name, component_signed(FIELD_NUMBER(item))));
    cardano_asset_name_unref(&name);
    name = NULL;
    cardano_blake2b_hash_unref(&policy);
    policy = NULL;
  }
  *result = assets;
  assets  = NULL;
cleanup:
  cardano_asset_name_unref(&name);
  name = NULL;
  cardano_blake2b_hash_unref(&policy);
  policy = NULL;
  cardano_multi_asset_unref(&assets);
  assets = NULL;
  return code;
}

static cardano_error_t
read_assets(cardano_multi_asset_t* assets, uint64_t coin, lean_object** result)
{
  cardano_policy_id_list_t* policies = NULL;
  cardano_blake2b_hash_t*   policy   = NULL;
  cardano_asset_name_map_t* names    = NULL;
  cardano_asset_name_t*     name     = NULL;
  lean_object*              entries  = lean_box(0);
  cardano_error_t           code     = CARDANO_SUCCESS;
  if (assets != NULL)
  {
    TRY(cardano_multi_asset_get_keys(assets, &policies));
    for (size_t i = 0; i < cardano_policy_id_list_get_length(policies); ++i)
    {
      TRY(cardano_policy_id_list_get(policies, i, &policy));
      /* Reject duplicate policies before getters could hide one of their maps. */
      for (size_t j = 0; j < i; ++j)
      {
        cardano_blake2b_hash_t* previous = NULL;
        code                             = cardano_policy_id_list_get(policies, j, &previous);
        bool duplicate                   = code == CARDANO_SUCCESS && cardano_blake2b_hash_equals(policy, previous);
        cardano_blake2b_hash_unref(&previous);
        previous = NULL;
        if (duplicate)
          code = CARDANO_ERROR_INVALID_ARGUMENT;
        if (code != CARDANO_SUCCESS)
          goto cleanup;
      }
      TRY(cardano_multi_asset_get_assets(assets, policy, &names));
      for (size_t j = 0; j < cardano_asset_name_map_get_length(names); ++j)
      {
        int64_t amount = 0;
        TRY(cardano_asset_name_map_get_key_value_at(names, j, &name, &amount));
        lean_object* entry = component_node(0, (uint64_t)amount, copy_bytes(cardano_blake2b_hash_get_data(policy), cardano_blake2b_hash_get_bytes_size(policy)), copy_bytes(cardano_asset_name_get_bytes(name), cardano_asset_name_get_bytes_size(name)), lean_mk_string(""), lean_box(0));
        entries            = component_cons(entry, entries);
        cardano_asset_name_unref(&name);
        name = NULL;
      }
      cardano_asset_name_map_unref(&names);
      names = NULL;
      cardano_blake2b_hash_unref(&policy);
      policy = NULL;
    }
  }
  *result = component_node(0, coin, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(entries));
  entries = lean_box(0);
cleanup:
  lean_dec(entries);
  cardano_asset_name_unref(&name);
  name = NULL;
  cardano_asset_name_map_unref(&names);
  names = NULL;
  cardano_blake2b_hash_unref(&policy);
  policy = NULL;
  cardano_policy_id_list_unref(&policies);
  policies = NULL;
  return code;
}

static cardano_error_t
build_value(lean_object* node, cardano_value_t** result)
{
  cardano_multi_asset_t* assets = NULL;
  cardano_error_t        code   = build_assets(node, &assets);
  if (code == CARDANO_SUCCESS)
    code = cardano_value_new(component_signed(FIELD_NUMBER(node)), assets, result);
  cardano_multi_asset_unref(&assets);
  assets = NULL;
  return code;
}

static cardano_error_t
read_value(cardano_value_t* value, lean_object** result)
{
  cardano_multi_asset_t* assets = cardano_value_get_multi_asset(value);
  cardano_error_t        code   = read_assets(assets, (uint64_t)cardano_value_get_coin(value), result);
  cardano_multi_asset_unref(&assets);
  assets = NULL;
  return code;
}

/* PLUTUS DATA ***************************************************************/

static cardano_error_t build_data(lean_object* node, cardano_plutus_data_t** result);
static cardano_error_t read_data(cardano_plutus_data_t* value, lean_object** result);

static cardano_error_t
build_data(lean_object* node, cardano_plutus_data_t** result)
{
  cardano_plutus_list_t*        list   = NULL;
  cardano_plutus_map_t*         map    = NULL;
  cardano_constr_plutus_data_t* constr = NULL;
  cardano_plutus_data_t*        child  = NULL;
  cardano_plutus_data_t*        key    = NULL;
  cardano_error_t               code   = CARDANO_SUCCESS;
  const uint64_t                kind   = FIELD_KIND(node);
  if (kind == 3)
  {
    lean_object* text = FIELD_TEXT(node);
    return cardano_plutus_data_new_integer_from_string(lean_string_cstr(text), lean_string_size(text) - 1, 10, result);
  }
  if (kind == 4)
  {
    lean_object* bytes = FIELD_BYTES(node);
    return cardano_plutus_data_new_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), result);
  }
  if (kind == 1)
    TRY(cardano_plutus_map_new(&map));
  else if (kind == 0 || kind == 2)
    TRY(cardano_plutus_list_new(&list));
  else
    return CARDANO_ERROR_INVALID_ARGUMENT;

  for (lean_object* items = FIELD_CHILDREN(node); !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(build_data(lean_ctor_get(items, 0), &child));
    if (kind == 1)
    {
      if (key == NULL)
      {
        key   = child;
        child = NULL;
      }
      else
      {
        TRY(cardano_plutus_map_insert(map, key, child));
        cardano_plutus_data_unref(&key);
        key = NULL;
      }
    }
    else
      TRY(cardano_plutus_list_add(list, child));
    cardano_plutus_data_unref(&child);
    child = NULL;
  }
  if (key != NULL)
  {
    code = CARDANO_ERROR_INVALID_ARGUMENT;
    goto cleanup;
  }
  if (kind == 0)
  {
    TRY(cardano_constr_plutus_data_new(FIELD_NUMBER(node), list, &constr));
    TRY(cardano_plutus_data_new_constr(constr, result));
  }
  else if (kind == 1)
    TRY(cardano_plutus_data_new_map(map, result));
  else
    TRY(cardano_plutus_data_new_list(list, result));
cleanup:
  cardano_plutus_data_unref(&key);
  key = NULL;
  cardano_plutus_data_unref(&child);
  child = NULL;
  cardano_plutus_list_unref(&list);
  list = NULL;
  cardano_plutus_map_unref(&map);
  map = NULL;
  cardano_constr_plutus_data_unref(&constr);
  constr = NULL;
  return code;
}

static cardano_error_t
read_data(cardano_plutus_data_t* value, lean_object** result)
{
  cardano_plutus_data_kind_t    kind;
  uint64_t                      alternative = 0;
  cardano_plutus_list_t*        list        = NULL;
  cardano_plutus_list_t*        values      = NULL;
  cardano_plutus_map_t*         map         = NULL;
  cardano_constr_plutus_data_t* constr      = NULL;
  cardano_plutus_data_t*        child       = NULL;
  cardano_bigint_t*             integer     = NULL;
  cardano_buffer_t*             buffer      = NULL;
  char*                         decimal     = NULL;
  lean_object*                  children    = lean_box(0);
  lean_object*                  bytes       = copy_bytes(NULL, 0);
  lean_object*                  text        = lean_mk_string("");
  lean_object*                  snapshot    = NULL;
  cardano_error_t               code;
  TRY(cardano_plutus_data_get_kind(value, &kind));
  switch (kind)
  {
    case CARDANO_PLUTUS_DATA_KIND_CONSTR:
      TRY(cardano_plutus_data_to_constr(value, &constr));
      TRY(cardano_constr_plutus_data_get_alternative(constr, &alternative));
      TRY(cardano_constr_plutus_data_get_data(constr, &list));
      break;
    case CARDANO_PLUTUS_DATA_KIND_LIST:
      TRY(cardano_plutus_data_to_list(value, &list));
      break;
    case CARDANO_PLUTUS_DATA_KIND_MAP:
      TRY(cardano_plutus_data_to_map(value, &map));
      TRY(cardano_plutus_map_get_keys(map, &list));
      TRY(cardano_plutus_map_get_values(map, &values));
      break;
    case CARDANO_PLUTUS_DATA_KIND_INTEGER:
      TRY(cardano_plutus_data_to_integer(value, &integer));
      {
        size_t size = cardano_bigint_get_string_size(integer, 10);
        decimal     = malloc(size);
        if (decimal == NULL)
        {
          code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
          goto cleanup;
        }
        TRY(cardano_bigint_to_string(integer, decimal, size, 10));
        lean_dec(text);
        text = lean_mk_string(decimal);
      }
      break;
    case CARDANO_PLUTUS_DATA_KIND_BYTES:
      TRY(cardano_plutus_data_to_bounded_bytes(value, &buffer));
      lean_dec(bytes);
      bytes = copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer));
      break;
    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
      goto cleanup;
  }
  if (list != NULL)
  {
    for (size_t i = 0; i < cardano_plutus_list_get_length(list); ++i)
    {
      TRY(cardano_plutus_list_get(list, i, &child));
      TRY(read_data(child, &snapshot));
      children = component_cons(snapshot, children);
      snapshot = NULL;
      cardano_plutus_data_unref(&child);
      child = NULL;
      if (values != NULL)
      {
        TRY(cardano_plutus_list_get(values, i, &child));
        TRY(read_data(child, &snapshot));
        children = component_cons(snapshot, children);
        snapshot = NULL;
        cardano_plutus_data_unref(&child);
        child = NULL;
      }
    }
  }
  *result = component_node(kind, alternative, bytes, copy_bytes(NULL, 0), text, component_reverse(children));
  bytes = text = children = lean_box(0);
cleanup:
  lean_dec(bytes);
  lean_dec(text);
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  free(decimal);
  cardano_buffer_unref(&buffer);
  buffer = NULL;
  cardano_bigint_unref(&integer);
  integer = NULL;
  cardano_plutus_data_unref(&child);
  child = NULL;
  cardano_constr_plutus_data_unref(&constr);
  constr = NULL;
  cardano_plutus_map_unref(&map);
  map = NULL;
  cardano_plutus_list_unref(&list);
  list = NULL;
  cardano_plutus_list_unref(&values);
  values = NULL;
  return code;
}

/* NATIVE SCRIPTS ************************************************************/

static cardano_error_t build_native_script(lean_object* node, cardano_native_script_t** result);
static cardano_error_t read_native_script(cardano_native_script_t* value, lean_object** result);

static cardano_error_t
build_native_script(lean_object* node, cardano_native_script_t** result)
{
  cardano_error_t                  code           = CARDANO_SUCCESS;
  cardano_native_script_list_t*    list           = NULL;
  cardano_native_script_t*         child          = NULL;
  cardano_blake2b_hash_t*          hash           = NULL;
  cardano_credential_t*            credential     = NULL;
  cardano_script_pubkey_t*         pubkey         = NULL;
  cardano_script_all_t*            all            = NULL;
  cardano_script_any_t*            any            = NULL;
  cardano_script_n_of_k_t*         n_of_k         = NULL;
  cardano_script_invalid_before_t* invalid_before = NULL;
  cardano_script_invalid_after_t*  invalid_after  = NULL;
  cardano_script_require_guard_t*  require_guard  = NULL;

  const uint64_t kind = FIELD_KIND(node);
  if (kind >= 1 && kind <= 3)
  {
    TRY(cardano_native_script_list_new(&list));
    for (lean_object* items = FIELD_CHILDREN(node); !lean_is_scalar(items); items = lean_ctor_get(items, 1))
    {
      TRY(build_native_script(lean_ctor_get(items, 0), &child));
      TRY(cardano_native_script_list_add(list, child));
      cardano_native_script_unref(&child);
      child = NULL;
    }
  }
  switch (kind)
  {
    case 0:
      TRY(cardano_blake2b_hash_from_bytes(lean_sarray_cptr(FIELD_BYTES(node)), lean_sarray_size(FIELD_BYTES(node)), &hash));
      TRY(cardano_script_pubkey_new(hash, &pubkey));
      TRY(cardano_native_script_new_pubkey(pubkey, result));
      break;
    case 1:
      TRY(cardano_script_all_new(list, &all));
      TRY(cardano_native_script_new_all(all, result));
      break;
    case 2:
      TRY(cardano_script_any_new(list, &any));
      TRY(cardano_native_script_new_any(any, result));
      break;
    case 3:
      TRY(cardano_script_n_of_k_new(list, FIELD_NUMBER(node), &n_of_k));
      TRY(cardano_native_script_new_n_of_k(n_of_k, result));
      break;
    case 4:
      TRY(cardano_script_invalid_before_new(FIELD_NUMBER(node), &invalid_before));
      TRY(cardano_native_script_new_invalid_before(invalid_before, result));
      break;
    case 5:
      TRY(cardano_script_invalid_after_new(FIELD_NUMBER(node), &invalid_after));
      TRY(cardano_native_script_new_invalid_after(invalid_after, result));
      break;

    case 6:
      if (lean_is_scalar(FIELD_CHILDREN(node)))
      {
        code = CARDANO_ERROR_INVALID_ARGUMENT;
        goto cleanup;
      }
      TRY(build_credential(lean_ctor_get(FIELD_CHILDREN(node), 0), &credential));
      TRY(cardano_script_require_guard_new(credential, &require_guard));
      TRY(cardano_native_script_new_require_guard(require_guard, result));
      break;
    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
  }
cleanup:
  cardano_native_script_unref(&child);
  child = NULL;
  cardano_native_script_list_unref(&list);
  list = NULL;
  cardano_blake2b_hash_unref(&hash);
  hash = NULL;
  cardano_credential_unref(&credential);
  credential = NULL;
  cardano_script_pubkey_unref(&pubkey);
  pubkey = NULL;
  cardano_script_all_unref(&all);
  all = NULL;
  cardano_script_any_unref(&any);
  any = NULL;
  cardano_script_n_of_k_unref(&n_of_k);
  n_of_k = NULL;
  cardano_script_invalid_before_unref(&invalid_before);
  invalid_before = NULL;
  cardano_script_invalid_after_unref(&invalid_after);
  invalid_after = NULL;
  cardano_script_require_guard_unref(&require_guard);
  require_guard = NULL;
  return code;
}

static cardano_error_t
read_native_script(cardano_native_script_t* value, lean_object** result)
{
  cardano_error_t                  code;
  cardano_native_script_type_t     kind;
  uint64_t                         number         = 0;
  cardano_native_script_list_t*    list           = NULL;
  cardano_native_script_t*         child          = NULL;
  cardano_blake2b_hash_t*          hash           = NULL;
  cardano_credential_t*            credential     = NULL;
  lean_object*                     bytes          = copy_bytes(NULL, 0);
  lean_object*                     children       = lean_box(0);
  lean_object*                     snapshot       = NULL;
  cardano_script_pubkey_t*         pubkey         = NULL;
  cardano_script_all_t*            all            = NULL;
  cardano_script_any_t*            any            = NULL;
  cardano_script_n_of_k_t*         n_of_k         = NULL;
  cardano_script_invalid_before_t* invalid_before = NULL;
  cardano_script_invalid_after_t*  invalid_after  = NULL;
  cardano_script_require_guard_t*  require_guard  = NULL;
  TRY(cardano_native_script_get_type(value, &kind));
  switch (kind)
  {
    case 0:
      TRY(cardano_native_script_to_pubkey(value, &pubkey));
      TRY(cardano_script_pubkey_get_key_hash(pubkey, &hash));
      lean_dec(bytes);
      bytes = copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash));
      break;
    case 1:
      TRY(cardano_native_script_to_all(value, &all));
      TRY(cardano_script_all_get_scripts(all, &list));
      break;
    case 2:
      TRY(cardano_native_script_to_any(value, &any));
      TRY(cardano_script_any_get_scripts(any, &list));
      break;
    case 3:
      TRY(cardano_native_script_to_n_of_k(value, &n_of_k));
      TRY(cardano_script_n_of_k_get_scripts(n_of_k, &list));
      number = cardano_script_n_of_k_get_required(n_of_k);
      break;
    case 4:
      TRY(cardano_native_script_to_invalid_before(value, &invalid_before));
      TRY(cardano_script_invalid_before_get_slot(invalid_before, &number));
      break;
    case 5:
      TRY(cardano_native_script_to_invalid_after(value, &invalid_after));
      TRY(cardano_script_invalid_after_get_slot(invalid_after, &number));
      break;
    case 6:
      TRY(cardano_native_script_to_require_guard(value, &require_guard));
      TRY(cardano_script_require_guard_get_credential(require_guard, &credential));
      TRY(read_credential(credential, &snapshot));
      children = component_cons(snapshot, children);
      snapshot = NULL;
      break;

    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
      goto cleanup;
  }
  if (list != NULL)
  {
    for (size_t i = 0; i < cardano_native_script_list_get_length(list); ++i)
    {
      TRY(cardano_native_script_list_get(list, i, &child));
      TRY(read_native_script(child, &snapshot));
      children = component_cons(snapshot, children);
      snapshot = NULL;
      cardano_native_script_unref(&child);
      child = NULL;
    }
  }
  *result = component_node(kind, number, bytes, copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children));
  bytes = children = lean_box(0);
cleanup:
  lean_dec(bytes);
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_native_script_unref(&child);
  child = NULL;
  cardano_native_script_list_unref(&list);
  list = NULL;
  cardano_blake2b_hash_unref(&hash);
  hash = NULL;
  cardano_credential_unref(&credential);
  credential = NULL;
  cardano_script_pubkey_unref(&pubkey);
  pubkey = NULL;
  cardano_script_all_unref(&all);
  all = NULL;
  cardano_script_any_unref(&any);
  any = NULL;
  cardano_script_n_of_k_unref(&n_of_k);
  n_of_k = NULL;
  cardano_script_invalid_before_unref(&invalid_before);
  invalid_before = NULL;
  cardano_script_invalid_after_unref(&invalid_after);
  invalid_after = NULL;
  cardano_script_require_guard_unref(&require_guard);
  require_guard = NULL;
  return code;
}

/* SCRIPT ENVELOPES **********************************************************/

static cardano_error_t
build_script(lean_object* node, cardano_script_t** result)
{
  cardano_error_t             code   = CARDANO_SUCCESS;
  cardano_native_script_t*    native = NULL;
  cardano_plutus_v1_script_t* v1     = NULL;
  cardano_plutus_v2_script_t* v2     = NULL;
  cardano_plutus_v3_script_t* v3     = NULL;
  cardano_plutus_v4_script_t* v4     = NULL;

  switch (FIELD_KIND(node))
  {
    case 0:
      if (lean_is_scalar(FIELD_CHILDREN(node)))
      {
        code = CARDANO_ERROR_INVALID_ARGUMENT;
        goto cleanup;
      }
      TRY(build_native_script(lean_ctor_get(FIELD_CHILDREN(node), 0), &native));
      TRY(cardano_script_new_native(native, result));
      break;
    case 1:
      TRY(cardano_plutus_v1_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(node)), lean_sarray_size(FIELD_BYTES(node)), &v1));
      TRY(cardano_script_new_plutus_v1(v1, result));
      break;
    case 2:
      TRY(cardano_plutus_v2_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(node)), lean_sarray_size(FIELD_BYTES(node)), &v2));
      TRY(cardano_script_new_plutus_v2(v2, result));
      break;
    case 3:
      TRY(cardano_plutus_v3_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(node)), lean_sarray_size(FIELD_BYTES(node)), &v3));
      TRY(cardano_script_new_plutus_v3(v3, result));
      break;
    case 4:
      TRY(cardano_plutus_v4_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(node)), lean_sarray_size(FIELD_BYTES(node)), &v4));
      TRY(cardano_script_new_plutus_v4(v4, result));
      break;
    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
  }
cleanup:
  cardano_native_script_unref(&native);
  native = NULL;
  cardano_plutus_v1_script_unref(&v1);
  cardano_plutus_v2_script_unref(&v2);
  cardano_plutus_v3_script_unref(&v3);
  cardano_plutus_v4_script_unref(&v4);
  return code;
}

static cardano_error_t
read_script(cardano_script_t* value, lean_object** result)
{
  cardano_error_t             code;
  cardano_script_language_t   language;
  cardano_native_script_t*    native   = NULL;
  cardano_buffer_t*           buffer   = NULL;
  lean_object*                children = lean_box(0);
  lean_object*                snapshot = NULL;
  cardano_plutus_v1_script_t* v1       = NULL;
  cardano_plutus_v2_script_t* v2       = NULL;
  cardano_plutus_v3_script_t* v3       = NULL;
  cardano_plutus_v4_script_t* v4       = NULL;

  TRY(cardano_script_get_language(value, &language));
  switch (language)
  {
    case 0:
      TRY(cardano_script_to_native(value, &native));
      TRY(read_native_script(native, &snapshot));
      children = component_cons(snapshot, children);
      snapshot = NULL;
      break;
    case 1:
      TRY(cardano_script_to_plutus_v1(value, &v1));
      TRY(cardano_plutus_v1_script_to_raw_bytes(v1, &buffer));
      break;
    case 2:
      TRY(cardano_script_to_plutus_v2(value, &v2));
      TRY(cardano_plutus_v2_script_to_raw_bytes(v2, &buffer));
      break;
    case 3:
      TRY(cardano_script_to_plutus_v3(value, &v3));
      TRY(cardano_plutus_v3_script_to_raw_bytes(v3, &buffer));
      break;
    case 4:
      TRY(cardano_script_to_plutus_v4(value, &v4));
      TRY(cardano_plutus_v4_script_to_raw_bytes(v4, &buffer));
      break;

    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
      goto cleanup;
  }
  *result  = component_node(language, 0, buffer == NULL ? copy_bytes(NULL, 0) : copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer)), copy_bytes(NULL, 0), lean_mk_string(""), children);
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_buffer_unref(&buffer);
  buffer = NULL;
  cardano_native_script_unref(&native);
  native = NULL;
  cardano_plutus_v1_script_unref(&v1);
  cardano_plutus_v2_script_unref(&v2);
  cardano_plutus_v3_script_unref(&v3);
  cardano_plutus_v4_script_unref(&v4);
  return code;
}

/* NATIVE CODEC HELPERS ******************************************************/

static cardano_error_t
parse_credential(lean_object* bytes, cardano_credential_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_credential_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_credential(cardano_credential_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_credential_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

static cardano_error_t
parse_value(lean_object* bytes, cardano_value_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_value_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_value(cardano_value_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_value_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

static cardano_error_t
parse_assets(lean_object* bytes, cardano_multi_asset_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_multi_asset_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_assets(cardano_multi_asset_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_multi_asset_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

static cardano_error_t
parse_data(lean_object* bytes, cardano_plutus_data_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_plutus_data_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_data(cardano_plutus_data_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_plutus_data_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

static cardano_error_t
parse_native_script(lean_object* bytes, cardano_native_script_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_native_script_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_native_script(cardano_native_script_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_native_script_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

static cardano_error_t
parse_script(lean_object* bytes, cardano_script_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_script_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = cardano_cbor_reader_read_end_array(reader);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_script(cardano_script_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_script_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

/* The pinned output parser overwrites repeated fields without releasing the
 * previous reference. Reject duplicate/missing map keys with the native reader
 * before invoking it. Field payload decoding still belongs to the native codec. */
static cardano_error_t
check_output_keys(lean_object* bytes)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_cbor_reader_state_t state;
  cardano_error_t             code;
  int64_t                     length;
  unsigned                    seen = 0;
  TRY(cardano_cbor_reader_peek_state(reader, &state));
  if (state != CARDANO_CBOR_READER_STATE_START_MAP)
    goto cleanup;
  TRY(cardano_cbor_reader_read_start_map(reader, &length));
  for (;;)
  {
    TRY(cardano_cbor_reader_peek_state(reader, &state));
    if (state == CARDANO_CBOR_READER_STATE_END_MAP)
      break;
    uint64_t key;
    TRY(cardano_cbor_reader_read_uint(reader, &key));
    if (key > 3 || (seen & (1U << key)) != 0)
    {
      code = CARDANO_ERROR_INVALID_CBOR_MAP_KEY;
      goto cleanup;
    }
    seen |= 1U << key;
    TRY(cardano_cbor_reader_skip_value(reader));
  }
  if ((seen & 3U) != 3U)
    code = CARDANO_ERROR_INVALID_CBOR_MAP_KEY;
cleanup:
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
parse_output(lean_object* bytes, cardano_transaction_output_t** result)
{
  cardano_error_t checked = check_output_keys(bytes);
  if (checked != CARDANO_SUCCESS)
    return checked;
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_output_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  reader = NULL;
  return code;
}

static cardano_error_t
serialize_output(cardano_transaction_output_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_output_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  return code;
}

/* OUTPUTS *******************************************************************/

static cardano_error_t
build_output(lean_object* node, cardano_transaction_output_t** result)
{
  cardano_address_t*            address = NULL;
  cardano_value_t*              value   = NULL;
  cardano_datum_t*              datum   = NULL;
  cardano_plutus_data_t*        data    = NULL;
  cardano_script_t*             script  = NULL;
  cardano_transaction_output_t* output  = NULL;
  cardano_error_t               code;
  lean_object*                  children = FIELD_CHILDREN(node);
  if (lean_is_scalar(children))
    return CARDANO_ERROR_INVALID_ARGUMENT;
  lean_object* value_node = lean_ctor_get(children, 0);
  children                = lean_ctor_get(children, 1);
  if (lean_is_scalar(children))
    return CARDANO_ERROR_INVALID_ARGUMENT;
  lean_object* datum_node = lean_ctor_get(children, 0);
  children                = lean_ctor_get(children, 1);
  if (lean_is_scalar(children))
    return CARDANO_ERROR_INVALID_ARGUMENT;
  lean_object* script_node = lean_ctor_get(children, 0);

  TRY(cardano_address_from_bytes(lean_sarray_cptr(FIELD_BYTES(node)), lean_sarray_size(FIELD_BYTES(node)), &address));
  TRY(build_value(value_node, &value));
  TRY(cardano_transaction_output_new(address, FIELD_NUMBER(value_node), &output));
  TRY(cardano_transaction_output_set_value(output, value));
  switch (FIELD_KIND(datum_node))
  {
    case 0:
      break;
    case 1:
      TRY(cardano_datum_new_data_hash_bytes(lean_sarray_cptr(FIELD_BYTES(datum_node)), lean_sarray_size(FIELD_BYTES(datum_node)), &datum));
      break;
    case 2:
      TRY(parse_data(FIELD_BYTES(datum_node), &data));
      TRY(cardano_datum_new_inline_data(data, &datum));
      break;
    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
      goto cleanup;
  }
  if (datum != NULL)
    TRY(cardano_transaction_output_set_datum(output, datum));
  if (FIELD_KIND(script_node) != 0)
  {
    TRY(parse_script(FIELD_BYTES(script_node), &script));
    TRY(cardano_transaction_output_set_script_ref(output, script));
  }
  *result = output;
  output  = NULL;
cleanup:
  cardano_transaction_output_unref(&output);
  output = NULL;
  cardano_address_unref(&address);
  address = NULL;
  cardano_value_unref(&value);
  value = NULL;
  cardano_datum_unref(&datum);
  datum = NULL;
  cardano_plutus_data_unref(&data);
  data = NULL;
  cardano_script_unref(&script);
  script = NULL;
  return code;
}

static cardano_error_t
read_output(cardano_transaction_output_t* output, lean_object** result)
{
  cardano_address_t*     address      = cardano_transaction_output_get_address(output);
  cardano_value_t*       value        = cardano_transaction_output_get_value(output);
  cardano_datum_t*       datum        = cardano_transaction_output_get_datum(output);
  cardano_script_t*      script       = cardano_transaction_output_get_script_ref(output);
  cardano_plutus_data_t* data         = NULL;
  lean_object*           value_node   = NULL;
  lean_object*           datum_bytes  = copy_bytes(NULL, 0);
  lean_object*           script_bytes = copy_bytes(NULL, 0);
  lean_object*           encoded      = NULL;
  uint64_t               datum_kind   = 0;
  cardano_error_t        code         = CARDANO_SUCCESS;
  if (address == NULL || value == NULL)
  {
    code = CARDANO_ERROR_POINTER_IS_NULL;
    goto cleanup;
  }
  TRY(read_value(value, &value_node));
  if (datum != NULL)
  {
    cardano_datum_type_t type;
    TRY(cardano_datum_get_type(datum, &type));
    if (type == CARDANO_DATUM_TYPE_DATA_HASH)
    {
      datum_kind = 1;
      lean_dec(datum_bytes);
      datum_bytes = copy_bytes(cardano_datum_get_data_hash_bytes(datum), cardano_datum_get_data_hash_bytes_size(datum));
    }
    else
    {
      datum_kind = 2;
      data       = cardano_datum_get_inline_data(datum);
      TRY(serialize_data(data, &encoded));
      lean_dec(datum_bytes);
      datum_bytes = encoded;
      encoded     = NULL;
    }
  }
  if (script != NULL)
  {
    TRY(serialize_script(script, &encoded));
    lean_dec(script_bytes);
    script_bytes = encoded;
    encoded      = NULL;
  }
  *result     = component_node(0, 0, copy_bytes(cardano_address_get_bytes(address), cardano_address_get_bytes_size(address)), copy_bytes(NULL, 0), lean_mk_string(""), component_cons(value_node, component_cons(component_leaf(datum_kind, 0, datum_bytes), component_cons(component_leaf(script == NULL ? 0 : 1, 0, script_bytes), lean_box(0)))));
  value_node  = NULL;
  datum_bytes = script_bytes = lean_box(0);
cleanup:
  if (value_node != NULL)
    lean_dec(value_node);
  if (encoded != NULL)
    lean_dec(encoded);
  lean_dec(datum_bytes);
  lean_dec(script_bytes);
  cardano_plutus_data_unref(&data);
  data = NULL;
  cardano_datum_unref(&datum);
  datum = NULL;
  cardano_script_unref(&script);
  script = NULL;
  cardano_value_unref(&value);
  value = NULL;
  cardano_address_unref(&address);
  address = NULL;
  return code;
}

/* Legacy representation is not exposed by the pinned output writer. Delegate
 * all scalar/value encoding to native writers; only choose the legacy container. */
static cardano_error_t
serialize_legacy_output(cardano_transaction_output_t* output, lean_object** result)
{
  cardano_address_t*     address = cardano_transaction_output_get_address(output);
  cardano_value_t*       value   = cardano_transaction_output_get_value(output);
  cardano_datum_t*       datum   = cardano_transaction_output_get_datum(output);
  cardano_cbor_writer_t* writer  = cardano_cbor_writer_new();
  cardano_error_t        code    = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  if (writer == NULL)
    goto cleanup;
  TRY(cardano_cbor_writer_write_start_array(writer, datum == NULL ? 2 : 3));
  TRY(cardano_cbor_writer_write_bytestring(writer, cardano_address_get_bytes(address), cardano_address_get_bytes_size(address)));
  TRY(cardano_value_to_cbor(value, writer));
  if (datum != NULL)
    TRY(cardano_cbor_writer_write_bytestring(writer, cardano_datum_get_data_hash_bytes(datum), cardano_datum_get_data_hash_bytes_size(datum)));
  TRY(component_writer_bytes(writer, result));
cleanup:
  cardano_cbor_writer_unref(&writer);
  writer = NULL;
  cardano_address_unref(&address);
  address = NULL;
  cardano_value_unref(&value);
  value = NULL;
  cardano_datum_unref(&datum);
  datum = NULL;
  return code;
}

#include "cometa_withdrawals.h"

/* Body assembly also uses the auxiliary-data helpers. */
#include "cometa_auxiliary.h"

/* Body construction depends on the helpers above. */
#include "cometa_transaction_build.h"

/* FOREIGN ENTRY POINTS ******************************************************/

/* Every family uses the concrete native constructors and codecs, not a second
 * ledger codec. Failure releases partial native objects and copied snapshots. */
LEAN_EXPORT lean_obj_res
cometa_lean_component_encode(uint8_t family, b_lean_obj_arg fields)
{
  cardano_error_t code  = CARDANO_ERROR_INVALID_ARGUMENT;
  lean_object*    bytes = NULL;
  switch (family)
  {
    case 14:
    {
      cardano_metadatum_t* value = NULL;
      code                       = build_metadatum(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_metadatum(value, &bytes);
      cardano_metadatum_unref(&value);
      break;
    }
    case 15:
    {
      cardano_transaction_metadata_t* value = NULL;
      code                                  = build_metadata(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_metadata(value, &bytes);
      cardano_transaction_metadata_unref(&value);
      break;
    }
    case 16:
    {
      cardano_auxiliary_data_t* value = NULL;
      code                            = build_auxiliary(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_auxiliary(value, &bytes);
      cardano_auxiliary_data_unref(&value);
      break;
    }
    case 12:
    {
      cardano_reward_address_t* value = NULL;
      code                            = build_reward(fields, &value);
      if (code == CARDANO_SUCCESS)
        bytes = copy_bytes(cardano_reward_address_get_bytes(value), cardano_reward_address_get_bytes_size(value));
      cardano_reward_address_unref(&value);
      break;
    }
    case 13:
    {
      cardano_withdrawal_map_t* value = NULL;
      code                            = build_withdrawals(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_withdrawals(value, &bytes);
      cardano_withdrawal_map_unref(&value);
      break;
    }
    case 8:
    {
      cardano_transaction_input_t* value = NULL;
      code                               = build_input(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_input(value, &bytes);
      cardano_transaction_input_unref(&value);
      break;
    }
    case 9:
    {
      cardano_transaction_input_set_t* value = NULL;
      code                                   = build_input_set(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_input_set(value, &bytes);
      cardano_transaction_input_set_unref(&value);
      break;
    }
    case 10:
    {
      cardano_utxo_t* value = NULL;
      code                  = build_utxo(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_utxo(value, &bytes);
      cardano_utxo_unref(&value);
      break;
    }
    case 11:
    {
      cardano_transaction_body_t* value = NULL;
      code                              = build_body(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_body(value, &bytes);
      cardano_transaction_body_unref(&value);
      break;
    }
    case 0:
    {
      cardano_credential_t* value = NULL;
      code                        = build_credential(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_credential(value, &bytes);
      cardano_credential_unref(&value);
      value = NULL;
      break;
    }
    case 1:
    {
      cardano_value_t* value = NULL;
      code                   = build_value(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_value(value, &bytes);
      cardano_value_unref(&value);
      value = NULL;
      break;
    }
    case 2:
    {
      cardano_multi_asset_t* value = NULL;
      code                         = build_assets(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_assets(value, &bytes);
      cardano_multi_asset_unref(&value);
      value = NULL;
      break;
    }
    case 3:
    {
      cardano_plutus_data_t* value = NULL;
      code                         = build_data(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_data(value, &bytes);
      cardano_plutus_data_unref(&value);
      value = NULL;
      break;
    }
    case 4:
    {
      cardano_native_script_t* value = NULL;
      code                           = build_native_script(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_native_script(value, &bytes);
      cardano_native_script_unref(&value);
      value = NULL;
      break;
    }
    case 5:
    {
      cardano_script_t* value = NULL;
      code                    = build_script(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = serialize_script(value, &bytes);
      cardano_script_unref(&value);
      value = NULL;
      break;
    }
    case 6:
    case 7:
    {
      cardano_transaction_output_t* value = NULL;
      code                                = build_output(fields, &value);
      if (code == CARDANO_SUCCESS)
        code = family == 7 ? serialize_legacy_output(value, &bytes) : serialize_output(value, &bytes);
      cardano_transaction_output_unref(&value);
      value = NULL;
      break;
    }
  }
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(bytes);
  if (bytes != NULL)
    lean_dec(bytes);
  return native_error(code);
}

LEAN_EXPORT lean_obj_res
cometa_lean_component_decode(uint8_t family, b_lean_obj_arg bytes)
{
  cardano_error_t code   = CARDANO_ERROR_INVALID_ARGUMENT;
  lean_object*    fields = NULL;
  switch (family)
  {
    case 14:
    {
      cardano_metadatum_t* value = NULL;
      code                       = parse_metadatum(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_metadatum(value, &fields);
      cardano_metadatum_unref(&value);
      break;
    }
    case 15:
    {
      cardano_transaction_metadata_t* value = NULL;
      code                                  = parse_metadata(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_metadata(value, &fields);
      cardano_transaction_metadata_unref(&value);
      break;
    }
    case 16:
    {
      cardano_auxiliary_data_t* value = NULL;
      code                            = parse_auxiliary(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_auxiliary(value, &fields);
      cardano_auxiliary_data_unref(&value);
      break;
    }
    case 12:
    {
      cardano_reward_address_t* value = NULL;
      code                            = parse_reward(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_reward(value, &fields);
      cardano_reward_address_unref(&value);
      break;
    }
    case 13:
    {
      cardano_withdrawal_map_t* value = NULL;
      code                            = parse_withdrawals(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_withdrawals(value, &fields);
      cardano_withdrawal_map_unref(&value);
      break;
    }
    case 8:
    {
      cardano_transaction_input_t* value = NULL;
      code                               = parse_input(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_input(value, &fields);
      cardano_transaction_input_unref(&value);
      break;
    }
    case 9:
    {
      cardano_transaction_input_set_t* value = NULL;
      code                                   = parse_input_set(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_input_set(value, &fields);
      cardano_transaction_input_set_unref(&value);
      break;
    }
    case 10:
    {
      cardano_utxo_t* value = NULL;
      code                  = parse_utxo(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_utxo(value, &fields);
      cardano_utxo_unref(&value);
      break;
    }
    case 11:
    {
      cardano_transaction_body_t* value = NULL;
      code                              = parse_body(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_body(value, &fields);
      cardano_transaction_body_unref(&value);
      break;
    }
    case 0:
    {
      cardano_credential_t* value = NULL;
      code                        = parse_credential(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_credential(value, &fields);
      cardano_credential_unref(&value);
      value = NULL;
      break;
    }
    case 1:
    {
      cardano_value_t* value = NULL;
      code                   = parse_value(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_value(value, &fields);
      cardano_value_unref(&value);
      value = NULL;
      break;
    }
    case 2:
    {
      cardano_multi_asset_t* value = NULL;
      code                         = parse_assets(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_assets(value, 0, &fields);
      cardano_multi_asset_unref(&value);
      value = NULL;
      break;
    }
    case 3:
    {
      cardano_plutus_data_t* value = NULL;
      code                         = parse_data(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_data(value, &fields);
      cardano_plutus_data_unref(&value);
      value = NULL;
      break;
    }
    case 4:
    {
      cardano_native_script_t* value = NULL;
      code                           = parse_native_script(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_native_script(value, &fields);
      cardano_native_script_unref(&value);
      value = NULL;
      break;
    }
    case 5:
    {
      cardano_script_t* value = NULL;
      code                    = parse_script(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_script(value, &fields);
      cardano_script_unref(&value);
      value = NULL;
      break;
    }
    case 6:
    {
      cardano_transaction_output_t* value = NULL;
      code                                = parse_output(bytes, &value);
      if (code == CARDANO_SUCCESS)
        code = read_output(value, &fields);
      cardano_transaction_output_unref(&value);
      value = NULL;
      break;
    }
  }
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(fields);
  if (fields != NULL)
    lean_dec(fields);
  return native_error(code);
}

#undef TRY
#undef FIELD_BYTES
#undef FIELD_EXTRA
#undef FIELD_TEXT
#undef FIELD_CHILDREN
#undef FIELD_KIND
#undef FIELD_NUMBER

#endif
