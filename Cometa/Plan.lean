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

import Cometa.Address
import Cometa.Lovelace

/-! Ordered payment intentions and pure accounting laws.

A plan is not a balanced or serialized transaction. The total excludes fees,
deposits, withdrawals, and minting; it may exceed the bound of one output amount.
The theorems describe this Lean model, not the behavior of native transaction code.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A lovelace payment to an address with a payment credential. -/
structure Payment where
  private mk ::
  /-- Recipient, excluding reward accounts. -/
  recipient : Address
  /-- Requested amount; minimum-output requirements are not checked here. -/
  amount : Lovelace

/-- A sequence of requested payments. Order and duplicate recipients are retained. -/
structure Plan where
  /-- Requested payments in their original order. -/
  payments : List Payment := []

-- DEFINITIONS ----------------------------------------------------------------

/-- Construct a payment, rejecting reward-account destinations. -/
def Payment.create (recipient : Address) (amount : Lovelace) : Except Error Payment :=
  if recipient.isPayment then
    .ok ⟨recipient, amount⟩
  else
    .error (.invalidInput "A reward account cannot receive a transaction output")

namespace Plan

/-- A plan with no payments. -/
def empty : Plan := ⟨[]⟩

/-- Request one validated payment. -/
def payTo (payment : Payment) : Plan := ⟨[payment]⟩

/-- Append payments, preserving order and duplicates. -/
def append (left right : Plan) : Plan := ⟨left.payments ++ right.payments⟩

instance : Append Plan := ⟨append⟩

/-- Sum requested lovelace using arbitrary-precision natural numbers. -/
def totalLovelace (plan : Plan) : Nat :=
  (plan.payments.map fun payment => payment.amount.value).sum

-- THEOREMS -------------------------------------------------------------------

/-- Composing plans preserves the sum of their requested payments. -/
@[simp] theorem totalLovelace_append (left right : Plan) :
    (left ++ right).totalLovelace = left.totalLovelace + right.totalLovelace := by
  change ((left.payments ++ right.payments).map fun p => p.amount.value).sum = _
  simp only [List.map_append, List.sum_append, totalLovelace]

/-- Payment composition is associative, including its observable ordering. -/
theorem append_assoc (first second third : Plan) :
    (first ++ second) ++ third = first ++ (second ++ third) := by
  change Plan.mk ((first.payments ++ second.payments) ++ third.payments) =
    Plan.mk (first.payments ++ (second.payments ++ third.payments))
  rw [List.append_assoc]

/-- An empty plan contributes no payments on the left. -/
@[simp] theorem empty_append (plan : Plan) : empty ++ plan = plan := by
  cases plan
  rfl

/-- An empty plan contributes no payments on the right. -/
@[simp] theorem append_empty (plan : Plan) : plan ++ empty = plan := by
  change Plan.mk (plan.payments ++ []) = plan
  simp only [List.append_nil]

end Plan
end Cometa
