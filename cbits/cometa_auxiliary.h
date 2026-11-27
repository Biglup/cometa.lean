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

#ifndef COMETA_AUXILIARY_H
#define COMETA_AUXILIARY_H

/* METADATA VALUES **********************************************************/

static cardano_error_t build_metadatum(lean_object* node, cardano_metadatum_t** result);
static cardano_error_t read_metadatum(cardano_metadatum_t* value, lean_object** result);

static cardano_error_t
build_metadatum(lean_object* node, cardano_metadatum_t** result)
{
  cardano_metadatum_list_t* list  = NULL;
  cardano_metadatum_map_t*  map   = NULL;
  cardano_metadatum_t*      child = NULL;
  cardano_metadatum_t*      key   = NULL;
  cardano_error_t           code  = CARDANO_SUCCESS;
  uint64_t                  kind  = FIELD_KIND(node);
  lean_object*              bytes = FIELD_BYTES(node);
  if (kind == 2)
    return cardano_metadatum_new_integer_from_string(lean_string_cstr(FIELD_TEXT(node)), lean_string_size(FIELD_TEXT(node)) - 1, 10, result);
  if (kind == 3)
    return cardano_metadatum_new_bytes(lean_sarray_cptr(bytes), lean_sarray_size(bytes), result);
  if (kind == 4)
    return cardano_metadatum_new_string((const char*)lean_sarray_cptr(bytes), lean_sarray_size(bytes), result);
  if (kind == 0)
    TRY(cardano_metadatum_map_new(&map));
  else if (kind == 1)
    TRY(cardano_metadatum_list_new(&list));
  else
    return CARDANO_ERROR_INVALID_ARGUMENT;
  for (lean_object* items = FIELD_CHILDREN(node); !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(build_metadatum(lean_ctor_get(items, 0), &child));
    if (kind == 0)
    {
      if (key == NULL)
      {
        key   = child;
        child = NULL;
      }
      else
      {
        TRY(cardano_metadatum_map_insert(map, key, child));
        cardano_metadatum_unref(&key);
        key = NULL;
      }
    }
    else
      TRY(cardano_metadatum_list_add(list, child));
    cardano_metadatum_unref(&child);
    child = NULL;
  }
  if (key != NULL)
  {
    code = CARDANO_ERROR_INVALID_ARGUMENT;
    goto cleanup;
  }
  if (kind == 0)
    TRY(cardano_metadatum_new_map(map, result));
  else
    TRY(cardano_metadatum_new_list(list, result));
cleanup:
  cardano_metadatum_unref(&key);
  cardano_metadatum_unref(&child);
  cardano_metadatum_list_unref(&list);
  cardano_metadatum_map_unref(&map);
  return code;
}

/* Getters acquire references. Text is copied by explicit byte length, including
 * embedded NULs; Lean checks UTF-8 before constructing its String value. */
static cardano_error_t
read_metadatum(cardano_metadatum_t* value, lean_object** result)
{
  cardano_metadatum_kind_t  kind;
  cardano_metadatum_list_t* list        = NULL;
  cardano_metadatum_map_t*  map         = NULL;
  cardano_metadatum_t*      key         = NULL;
  cardano_metadatum_t*      child       = NULL;
  cardano_bigint_t*         integer     = NULL;
  cardano_buffer_t*         buffer      = NULL;
  char*                     text_buffer = NULL;
  lean_object*              children    = lean_box(0);
  lean_object*              bytes       = copy_bytes(NULL, 0);
  lean_object*              text        = lean_mk_string("");
  lean_object*              snapshot    = NULL;
  cardano_error_t           code;
  TRY(cardano_metadatum_get_kind(value, &kind));
  switch (kind)
  {
    case CARDANO_METADATUM_KIND_MAP:
      TRY(cardano_metadatum_to_map(value, &map));
      for (size_t i = 0; i < cardano_metadatum_map_get_length(map); ++i)
      {
        TRY(cardano_metadatum_map_get_at(map, i, &key, &child));
        TRY(read_metadatum(key, &snapshot));
        children = component_cons(snapshot, children);
        snapshot = NULL;
        TRY(read_metadatum(child, &snapshot));
        children = component_cons(snapshot, children);
        snapshot = NULL;
        cardano_metadatum_unref(&key);
        key = NULL;
        cardano_metadatum_unref(&child);
        child = NULL;
      }
      break;
    case CARDANO_METADATUM_KIND_LIST:
      TRY(cardano_metadatum_to_list(value, &list));
      for (size_t i = 0; i < cardano_metadatum_list_get_length(list); ++i)
      {
        TRY(cardano_metadatum_list_get(list, i, &child));
        TRY(read_metadatum(child, &snapshot));
        children = component_cons(snapshot, children);
        snapshot = NULL;
        cardano_metadatum_unref(&child);
        child = NULL;
      }
      break;
    case CARDANO_METADATUM_KIND_INTEGER:
    {
      TRY(cardano_metadatum_to_integer(value, &integer));
      size_t size = cardano_bigint_get_string_size(integer, 10);
      text_buffer = malloc(size);
      if (text_buffer == NULL)
      {
        code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
        goto cleanup;
      }
      TRY(cardano_bigint_to_string(integer, text_buffer, size, 10));
      lean_dec(text);
      text = lean_mk_string(text_buffer);
      break;
    }
    case CARDANO_METADATUM_KIND_BYTES:
      TRY(cardano_metadatum_to_bounded_bytes(value, &buffer));
      lean_dec(bytes);
      bytes = copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer));
      break;
    case CARDANO_METADATUM_KIND_TEXT:
    {
      size_t size = cardano_metadatum_get_string_size(value);
      if (size == 0)
      {
        code = CARDANO_ERROR_INVALID_ARGUMENT;
        goto cleanup;
      }
      text_buffer = malloc(size);
      if (text_buffer == NULL)
      {
        code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
        goto cleanup;
      }
      TRY(cardano_metadatum_to_string(value, text_buffer, size));
      lean_dec(bytes);
      bytes = copy_bytes((const uint8_t*)text_buffer, size - 1);
      break;
    }
    default:
      code = CARDANO_ERROR_INVALID_ARGUMENT;
      goto cleanup;
  }
  *result = component_node(kind, 0, bytes, copy_bytes(NULL, 0), text, component_reverse(children));
  bytes = text = children = lean_box(0);
cleanup:
  lean_dec(bytes);
  lean_dec(text);
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  free(text_buffer);
  cardano_buffer_unref(&buffer);
  cardano_bigint_unref(&integer);
  cardano_metadatum_unref(&key);
  cardano_metadatum_unref(&child);
  cardano_metadatum_map_unref(&map);
  cardano_metadatum_list_unref(&list);
  return code;
}

/* LABEL MAPS ***************************************************************/

static cardano_error_t
build_metadata(lean_object* fields, cardano_transaction_metadata_t** result)
{
  cardano_transaction_metadata_t* metadata = NULL;
  cardano_metadatum_t*            value    = NULL;
  cardano_error_t                 code;
  TRY(cardano_transaction_metadata_new(&metadata));
  for (lean_object* list = FIELD_CHILDREN(fields); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    lean_object* entry    = lean_ctor_get(list, 0);
    lean_object* children = FIELD_CHILDREN(entry);
    if (lean_is_scalar(children) || !lean_is_scalar(lean_ctor_get(children, 1)))
    {
      code = CARDANO_ERROR_INVALID_ARGUMENT;
      goto cleanup;
    }
    TRY(build_metadatum(lean_ctor_get(children, 0), &value));
    TRY(cardano_transaction_metadata_insert(metadata, FIELD_NUMBER(entry), value));
    cardano_metadatum_unref(&value);
    value = NULL;
  }
  *result  = metadata;
  metadata = NULL;
cleanup:
  cardano_metadatum_unref(&value);
  cardano_transaction_metadata_unref(&metadata);
  return code;
}

static cardano_error_t
read_metadata(cardano_transaction_metadata_t* metadata, lean_object** result)
{
  cardano_metadatum_t* value    = NULL;
  lean_object*         entries  = lean_box(0);
  lean_object*         snapshot = NULL;
  cardano_error_t      code     = CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_transaction_metadata_get_length(metadata); ++i)
  {
    uint64_t label;
    TRY(cardano_transaction_metadata_get_key_value_at(metadata, i, &label, &value));
    TRY(read_metadatum(value, &snapshot));
    entries  = component_cons(component_node(0, label, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_cons(snapshot, lean_box(0))), entries);
    snapshot = NULL;
    cardano_metadatum_unref(&value);
    value = NULL;
  }
  *result = component_node(0, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(entries));
  entries = lean_box(0);
cleanup:
  lean_dec(entries);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_metadatum_unref(&value);
  return code;
}

/* NATIVE CODECS *************************************************************/

static cardano_error_t
parse_metadatum(lean_object* bytes, cardano_metadatum_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_metadatum_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_metadatum(cardano_metadatum_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_metadatum_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
parse_metadata(lean_object* bytes, cardano_transaction_metadata_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_metadata_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_metadata(cardano_transaction_metadata_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_transaction_metadata_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

static cardano_error_t
parse_auxiliary(lean_object* bytes, cardano_auxiliary_data_t** result)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_auxiliary_data_from_cbor(reader, result);
  if (code == CARDANO_SUCCESS)
    code = require_end(reader);
  cardano_cbor_reader_unref(&reader);
  return code;
}

static cardano_error_t
serialize_auxiliary(cardano_auxiliary_data_t* value, lean_object** result)
{
  cardano_cbor_writer_t* writer = cardano_cbor_writer_new();
  if (writer == NULL)
    return CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
  cardano_error_t code = cardano_auxiliary_data_to_cbor(value, writer);
  if (code == CARDANO_SUCCESS)
    code = component_writer_bytes(writer, result);
  cardano_cbor_writer_unref(&writer);
  return code;
}

/* AUXILIARY FIELDS **********************************************************/

static cardano_error_t
set_auxiliary_native_scripts(cardano_auxiliary_data_t* auxiliary, lean_object* children)
{
  cardano_native_script_list_t* list   = NULL;
  cardano_native_script_t*      script = NULL;
  cardano_error_t               code;
  TRY(cardano_native_script_list_new(&list));
  for (lean_object* items = children; !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(build_native_script(lean_ctor_get(items, 0), &script));
    TRY(cardano_native_script_list_add(list, script));
    cardano_native_script_unref(&script);
    script = NULL;
  }
  TRY(cardano_auxiliary_data_set_native_scripts(auxiliary, list));
cleanup:
  cardano_native_script_unref(&script);
  cardano_native_script_list_unref(&list);
  return code;
}

static cardano_error_t
read_auxiliary_native_scripts(cardano_auxiliary_data_t* auxiliary, lean_object** fields)
{
  cardano_native_script_list_t* list     = cardano_auxiliary_data_get_native_scripts(auxiliary);
  cardano_native_script_t*      script   = NULL;
  cardano_buffer_t*             buffer   = NULL;
  lean_object*                  children = lean_box(0);
  lean_object*                  snapshot = NULL;
  cardano_error_t               code     = CARDANO_SUCCESS;
  if (list == NULL)
    return CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_native_script_list_get_length(list); ++i)
  {
    TRY(cardano_native_script_list_get(list, i, &script));
    TRY(read_native_script(script, &snapshot));
    children = component_cons(snapshot, children);
    snapshot = NULL;
    cardano_native_script_unref(&script);
    script = NULL;
  }
  *fields  = component_cons(component_node(1, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children)), *fields);
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_buffer_unref(&buffer);
  cardano_native_script_unref(&script);
  cardano_native_script_list_unref(&list);
  return code;
}

static cardano_error_t
set_auxiliary_plutus_v1_scripts(cardano_auxiliary_data_t* auxiliary, lean_object* children)
{
  cardano_plutus_v1_script_list_t* list   = NULL;
  cardano_plutus_v1_script_t*      script = NULL;
  cardano_error_t                  code;
  TRY(cardano_plutus_v1_script_list_new(&list));
  for (lean_object* items = children; !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(cardano_plutus_v1_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(lean_ctor_get(items, 0))), lean_sarray_size(FIELD_BYTES(lean_ctor_get(items, 0))), &script));
    TRY(cardano_plutus_v1_script_list_add(list, script));
    cardano_plutus_v1_script_unref(&script);
    script = NULL;
  }
  TRY(cardano_auxiliary_data_set_plutus_v1_scripts(auxiliary, list));
cleanup:
  cardano_plutus_v1_script_unref(&script);
  cardano_plutus_v1_script_list_unref(&list);
  return code;
}

static cardano_error_t
read_auxiliary_plutus_v1_scripts(cardano_auxiliary_data_t* auxiliary, lean_object** fields)
{
  cardano_plutus_v1_script_list_t* list     = cardano_auxiliary_data_get_plutus_v1_scripts(auxiliary);
  cardano_plutus_v1_script_t*      script   = NULL;
  cardano_buffer_t*                buffer   = NULL;
  lean_object*                     children = lean_box(0);
  lean_object*                     snapshot = NULL;
  cardano_error_t                  code     = CARDANO_SUCCESS;
  if (list == NULL)
    return CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_plutus_v1_script_list_get_length(list); ++i)
  {
    TRY(cardano_plutus_v1_script_list_get(list, i, &script));
    TRY(cardano_plutus_v1_script_to_raw_bytes(script, &buffer));
    snapshot = component_leaf(0, 0, copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer)));
    cardano_buffer_unref(&buffer);
    buffer   = NULL;
    children = component_cons(snapshot, children);
    snapshot = NULL;
    cardano_plutus_v1_script_unref(&script);
    script = NULL;
  }
  *fields  = component_cons(component_node(2, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children)), *fields);
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_buffer_unref(&buffer);
  cardano_plutus_v1_script_unref(&script);
  cardano_plutus_v1_script_list_unref(&list);
  return code;
}

static cardano_error_t
set_auxiliary_plutus_v2_scripts(cardano_auxiliary_data_t* auxiliary, lean_object* children)
{
  cardano_plutus_v2_script_list_t* list   = NULL;
  cardano_plutus_v2_script_t*      script = NULL;
  cardano_error_t                  code;
  TRY(cardano_plutus_v2_script_list_new(&list));
  for (lean_object* items = children; !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(cardano_plutus_v2_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(lean_ctor_get(items, 0))), lean_sarray_size(FIELD_BYTES(lean_ctor_get(items, 0))), &script));
    TRY(cardano_plutus_v2_script_list_add(list, script));
    cardano_plutus_v2_script_unref(&script);
    script = NULL;
  }
  TRY(cardano_auxiliary_data_set_plutus_v2_scripts(auxiliary, list));
cleanup:
  cardano_plutus_v2_script_unref(&script);
  cardano_plutus_v2_script_list_unref(&list);
  return code;
}

static cardano_error_t
read_auxiliary_plutus_v2_scripts(cardano_auxiliary_data_t* auxiliary, lean_object** fields)
{
  cardano_plutus_v2_script_list_t* list     = cardano_auxiliary_data_get_plutus_v2_scripts(auxiliary);
  cardano_plutus_v2_script_t*      script   = NULL;
  cardano_buffer_t*                buffer   = NULL;
  lean_object*                     children = lean_box(0);
  lean_object*                     snapshot = NULL;
  cardano_error_t                  code     = CARDANO_SUCCESS;
  if (list == NULL)
    return CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_plutus_v2_script_list_get_length(list); ++i)
  {
    TRY(cardano_plutus_v2_script_list_get(list, i, &script));
    TRY(cardano_plutus_v2_script_to_raw_bytes(script, &buffer));
    snapshot = component_leaf(0, 0, copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer)));
    cardano_buffer_unref(&buffer);
    buffer   = NULL;
    children = component_cons(snapshot, children);
    snapshot = NULL;
    cardano_plutus_v2_script_unref(&script);
    script = NULL;
  }
  *fields  = component_cons(component_node(3, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children)), *fields);
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_buffer_unref(&buffer);
  cardano_plutus_v2_script_unref(&script);
  cardano_plutus_v2_script_list_unref(&list);
  return code;
}

static cardano_error_t
set_auxiliary_plutus_v3_scripts(cardano_auxiliary_data_t* auxiliary, lean_object* children)
{
  cardano_plutus_v3_script_list_t* list   = NULL;
  cardano_plutus_v3_script_t*      script = NULL;
  cardano_error_t                  code;
  TRY(cardano_plutus_v3_script_list_new(&list));
  for (lean_object* items = children; !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(cardano_plutus_v3_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(lean_ctor_get(items, 0))), lean_sarray_size(FIELD_BYTES(lean_ctor_get(items, 0))), &script));
    TRY(cardano_plutus_v3_script_list_add(list, script));
    cardano_plutus_v3_script_unref(&script);
    script = NULL;
  }
  TRY(cardano_auxiliary_data_set_plutus_v3_scripts(auxiliary, list));
cleanup:
  cardano_plutus_v3_script_unref(&script);
  cardano_plutus_v3_script_list_unref(&list);
  return code;
}

static cardano_error_t
read_auxiliary_plutus_v3_scripts(cardano_auxiliary_data_t* auxiliary, lean_object** fields)
{
  cardano_plutus_v3_script_list_t* list     = cardano_auxiliary_data_get_plutus_v3_scripts(auxiliary);
  cardano_plutus_v3_script_t*      script   = NULL;
  cardano_buffer_t*                buffer   = NULL;
  lean_object*                     children = lean_box(0);
  lean_object*                     snapshot = NULL;
  cardano_error_t                  code     = CARDANO_SUCCESS;
  if (list == NULL)
    return CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_plutus_v3_script_list_get_length(list); ++i)
  {
    TRY(cardano_plutus_v3_script_list_get(list, i, &script));
    TRY(cardano_plutus_v3_script_to_raw_bytes(script, &buffer));
    snapshot = component_leaf(0, 0, copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer)));
    cardano_buffer_unref(&buffer);
    buffer   = NULL;
    children = component_cons(snapshot, children);
    snapshot = NULL;
    cardano_plutus_v3_script_unref(&script);
    script = NULL;
  }
  *fields  = component_cons(component_node(4, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children)), *fields);
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_buffer_unref(&buffer);
  cardano_plutus_v3_script_unref(&script);
  cardano_plutus_v3_script_list_unref(&list);
  return code;
}

static cardano_error_t
set_auxiliary_plutus_v4_scripts(cardano_auxiliary_data_t* auxiliary, lean_object* children)
{
  cardano_plutus_v4_script_list_t* list   = NULL;
  cardano_plutus_v4_script_t*      script = NULL;
  cardano_error_t                  code;
  TRY(cardano_plutus_v4_script_list_new(&list));
  for (lean_object* items = children; !lean_is_scalar(items); items = lean_ctor_get(items, 1))
  {
    TRY(cardano_plutus_v4_script_new_bytes(lean_sarray_cptr(FIELD_BYTES(lean_ctor_get(items, 0))), lean_sarray_size(FIELD_BYTES(lean_ctor_get(items, 0))), &script));
    TRY(cardano_plutus_v4_script_list_add(list, script));
    cardano_plutus_v4_script_unref(&script);
    script = NULL;
  }
  TRY(cardano_auxiliary_data_set_plutus_v4_scripts(auxiliary, list));
cleanup:
  cardano_plutus_v4_script_unref(&script);
  cardano_plutus_v4_script_list_unref(&list);
  return code;
}

static cardano_error_t
read_auxiliary_plutus_v4_scripts(cardano_auxiliary_data_t* auxiliary, lean_object** fields)
{
  cardano_plutus_v4_script_list_t* list     = cardano_auxiliary_data_get_plutus_v4_scripts(auxiliary);
  cardano_plutus_v4_script_t*      script   = NULL;
  cardano_buffer_t*                buffer   = NULL;
  lean_object*                     children = lean_box(0);
  lean_object*                     snapshot = NULL;
  cardano_error_t                  code     = CARDANO_SUCCESS;
  if (list == NULL)
    return CARDANO_SUCCESS;
  for (size_t i = 0; i < cardano_plutus_v4_script_list_get_length(list); ++i)
  {
    TRY(cardano_plutus_v4_script_list_get(list, i, &script));
    TRY(cardano_plutus_v4_script_to_raw_bytes(script, &buffer));
    snapshot = component_leaf(0, 0, copy_bytes(cardano_buffer_get_data(buffer), cardano_buffer_get_size(buffer)));
    cardano_buffer_unref(&buffer);
    buffer   = NULL;
    children = component_cons(snapshot, children);
    snapshot = NULL;
    cardano_plutus_v4_script_unref(&script);
    script = NULL;
  }
  *fields  = component_cons(component_node(5, 0, copy_bytes(NULL, 0), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(children)), *fields);
  children = lean_box(0);
cleanup:
  lean_dec(children);
  if (snapshot != NULL)
    lean_dec(snapshot);
  cardano_buffer_unref(&buffer);
  cardano_plutus_v4_script_unref(&script);
  cardano_plutus_v4_script_list_unref(&list);
  return code;
}

static cardano_error_t
build_auxiliary(lean_object* fields, cardano_auxiliary_data_t** result)
{
  cardano_auxiliary_data_t*       auxiliary = NULL;
  cardano_transaction_metadata_t* metadata  = NULL;
  cardano_error_t                 code;
  TRY(cardano_auxiliary_data_new(&auxiliary));
  for (lean_object* list = FIELD_CHILDREN(fields); !lean_is_scalar(list); list = lean_ctor_get(list, 1))
  {
    lean_object* field = lean_ctor_get(list, 0);
    switch (FIELD_KIND(field))
    {
      case 0:
        TRY(parse_metadata(FIELD_BYTES(field), &metadata));
        TRY(cardano_auxiliary_data_set_transaction_metadata(auxiliary, metadata));
        cardano_transaction_metadata_unref(&metadata);
        metadata = NULL;
        break;
      case 1:
        TRY(set_auxiliary_native_scripts(auxiliary, FIELD_CHILDREN(field)));
        break;
      case 2:
        TRY(set_auxiliary_plutus_v1_scripts(auxiliary, FIELD_CHILDREN(field)));
        break;
      case 3:
        TRY(set_auxiliary_plutus_v2_scripts(auxiliary, FIELD_CHILDREN(field)));
        break;
      case 4:
        TRY(set_auxiliary_plutus_v3_scripts(auxiliary, FIELD_CHILDREN(field)));
        break;
      case 5:
        TRY(set_auxiliary_plutus_v4_scripts(auxiliary, FIELD_CHILDREN(field)));
        break;
      default:
        code = CARDANO_ERROR_INVALID_ARGUMENT;
        goto cleanup;
    }
  }
  *result   = auxiliary;
  auxiliary = NULL;
cleanup:
  cardano_transaction_metadata_unref(&metadata);
  cardano_auxiliary_data_unref(&auxiliary);
  return code;
}

static cardano_error_t
read_auxiliary(cardano_auxiliary_data_t* auxiliary, lean_object** result)
{
  cardano_transaction_metadata_t* metadata = cardano_auxiliary_data_get_transaction_metadata(auxiliary);
  cardano_blake2b_hash_t*         hash     = NULL;
  lean_object*                    fields   = lean_box(0);
  lean_object*                    bytes    = NULL;
  cardano_error_t                 code;
  if (metadata != NULL)
  {
    TRY(serialize_metadata(metadata, &bytes));
    fields = component_cons(component_leaf(0, 0, bytes), fields);
    bytes  = NULL;
  }
  TRY(read_auxiliary_native_scripts(auxiliary, &fields));
  TRY(read_auxiliary_plutus_v1_scripts(auxiliary, &fields));
  TRY(read_auxiliary_plutus_v2_scripts(auxiliary, &fields));
  TRY(read_auxiliary_plutus_v3_scripts(auxiliary, &fields));
  TRY(read_auxiliary_plutus_v4_scripts(auxiliary, &fields));
  hash = cardano_auxiliary_data_get_hash(auxiliary);
  if (hash == NULL)
  {
    code = CARDANO_ERROR_MEMORY_ALLOCATION_FAILED;
    goto cleanup;
  }
  *result = component_node(0, 0, copy_bytes(cardano_blake2b_hash_get_data(hash), cardano_blake2b_hash_get_bytes_size(hash)), copy_bytes(NULL, 0), lean_mk_string(""), component_reverse(fields));
  fields  = lean_box(0);
cleanup:
  if (bytes != NULL)
    lean_dec(bytes);
  lean_dec(fields);
  cardano_blake2b_hash_unref(&hash);
  cardano_transaction_metadata_unref(&metadata);
  return code;
}

/* Borrow transaction bytes and copy the optional auxiliary cache. An empty byte
 * array represents absence; valid auxiliary CBOR always contains at least a map. */
LEAN_EXPORT lean_obj_res
cometa_lean_transaction_auxiliary(b_lean_obj_arg bytes)
{
  cardano_cbor_reader_t* reader = cardano_cbor_reader_new(lean_sarray_cptr(bytes), lean_sarray_size(bytes));
  if (reader == NULL)
    return native_error(CARDANO_ERROR_MEMORY_ALLOCATION_FAILED);
  cardano_transaction_t*    transaction = NULL;
  cardano_auxiliary_data_t* auxiliary   = NULL;
  lean_object*              result      = NULL;
  cardano_error_t           code;
  TRY(check_transaction_key_witnesses(bytes));
  TRY(cardano_transaction_from_cbor(reader, &transaction));
  TRY(require_end(reader));
  auxiliary = cardano_transaction_get_auxiliary_data(transaction);
  if (auxiliary == NULL)
    result = copy_bytes(NULL, 0);
  else
    TRY(serialize_auxiliary(auxiliary, &result));
cleanup:
  cardano_auxiliary_data_unref(&auxiliary);
  cardano_transaction_unref(&transaction);
  cardano_cbor_reader_unref(&reader);
  if (code == CARDANO_SUCCESS)
    return lean_io_result_mk_ok(result);
  if (result != NULL)
    lean_dec(result);
  return native_error(code);
}

#endif
