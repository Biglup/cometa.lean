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

/-! Inspect an address and construct a payment intention. This example does not
build, sign, or submit a transaction. Run `lake exe inspectAddress ADDRESS LOVELACE`.
-/

open Cometa

-- DEFINITIONS ----------------------------------------------------------------

/-- Validate the amount and payment destination together, before constructing a plan. -/
private def paymentPlan (recipient : Address) (text : String) : Except Error Plan := do
  let some value := text.toNat?
    | throw (.invalidInput "Amount must be a decimal nonnegative integer")
  let amount ← Lovelace.ofNat value
  let payment ← Payment.create recipient amount
  return Plan.payTo payment

/-- Parse the address through cardano-c and assemble a Lean-owned plan. -/
private def inspect (addressText amountText : String) : EIO Error Plan := do
  let recipient ← Address.ofString addressText
  EIO.ofExcept (paymentPlan recipient amountText)

/-- Keep the application error boundary and all output in one place. -/
def main (args : List String) : IO UInt32 := do
  let [addressText, amountText] := args
    | IO.eprintln "Usage: inspectAddress ADDRESS LOVELACE"; return 1

  match ← (inspect addressText amountText).toIO' with
  | .error error =>
    IO.eprintln s!"{error}"
    return 1
  | .ok plan =>
    for payment in plan.payments do
      IO.println s!"Recipient: {payment.recipient}"
      IO.println s!"Lovelace: {payment.amount}"
    IO.println s!"Total requested: {plan.totalLovelace} lovelace"
    return 0
