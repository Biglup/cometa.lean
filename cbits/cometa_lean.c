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
