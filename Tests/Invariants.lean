/-
Copyright 2026 Biglup Labs
SPDX-License-Identifier: Apache-2.0

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-/

import Cometa

/-! Compile-time checks that ordinary construction cannot bypass validation. -/

open Cometa

-- CONSTRUCTION BOUNDARIES -----------------------------------------------------

/-- error: Unknown constant `Cometa.Address.mk` -/
#guard_msgs in
#check Address.mk

/-- error: invalid {...} notation, constructor for `Payment` is marked as private -/
#guard_msgs in
example (payment : Payment) (recipient : Address) : Payment :=
  { payment with recipient := recipient }

/-- error: Unknown constant `Cometa.Payment.mk` -/
#guard_msgs in
#check Payment.mk

-- MODEL LAWS -----------------------------------------------------------------

example (left right : Plan) :
    (left ++ right).totalLovelace = left.totalLovelace + right.totalLovelace :=
  Plan.totalLovelace_append left right

-- INTERPRETER ---------------------------------------------------------------

/-- info: "2.0.0-rc.7" -/
#guard_msgs in
#eval nativeVersion
