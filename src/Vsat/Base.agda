------------------------------------------------------------------------
-- Variational Satisfiability Solver
--
--
-- Core algorithms and inference rules for Vsat
------------------------------------------------------------------------

module Vsat.Base where

open import Data.String using (String; _≈_; _==_; _≟_;_++_)
open import Relation.Binary.PropositionalEquality using (_≡_)
open import Data.List using (List; _∷_; []; _++_;lookup;length;any)
import Data.List.Relation.Unary.Any as A using (lookup)
open import Data.Product using (_×_; proj₁; proj₂; _,_)
open import Data.Bool using (Bool;true;false;T;if_then_else_)
open import Function using (_$_;_∘_)

import Data.List.Membership.DecPropositional as DecPropMembership

open import Utils.Base
open import Vpl.Base

------------------------------------------------------------------------
-------------------- Type Synonyms -------------------------------------
------------------------------------------------------------------------
Id : Set
Id = String

Dimension : Set
Dimension = String

Reference : Set
Reference = String

-- | A configuration is a mapping of dimensions to booleans
Config : Set
Config = List (Dimension × Bool)

-- | Γ is the context representing the base solver. We simulate the base solver
-- | using a set of references. For any reference, r, if r ∈ Γ then r has been
-- | sent to the base solver. Note that we assume Γ processes references,
-- | symbolic references and literals
Γ : Set
Γ = List String

------------------------------------------------------------------------
-------------------- Intemediate Lang ----------------------------------
------------------------------------------------------------------------
-- have to make a data type for symbolic in order to _unwind_ the variational
-- cores
data Symbolic : Set where
  sRef : String → Symbolic
  sLit : Bool   → Symbolic
  sNeg : Symbolic → Symbolic
  sOr  : Symbolic → Symbolic → Symbolic
  sAnd : Symbolic → Symbolic → Symbolic

data IL : Set where
  ●     : IL
  refIL : Reference → IL
  symIL : Symbolic  → IL
  litIL : Bool      → IL
  negIL : IL → IL
  andIL : IL → IL → IL
  orIL  : IL → IL → IL
  chcIL : String → Vpl → Vpl → IL

-- | the symbolic store, we associate Reference with symbolics but will also use
-- | Symbolic × Symbolic when needed such as Δ-negate
Δ : Set
Δ = List (Reference × Symbolic)
------------------------------------------------------------------------
------------------------ Symbolic Store Primitives ---------------------
------------------------------------------------------------------------
open DecPropMembership _≟_
open import Data.List.Relation.Unary.Any using (here; there;Any)
open import Relation.Nullary.Decidable using (⌊_⌋; True; toWitness; fromWitness)

Δ-spawn : Δ → Reference → (Δ × IL)
Δ-spawn store nm = (Δ' , (symIL $ sRef nm))
  where
  new : String
  new = fresh nm

  Δ' : Δ
  Δ' = (nm , sRef new) ∷ store

Δ-ref : ∀ {store : Δ} {name : Reference} → { name∈store : True (name ∈? (names store)) } → (Δ × IL)
Δ-ref {s} {_} {name∈store = name∈store} = s , (symIL ∘ sRef ∘ A.lookup ∘ toWitness $ name∈store)

-- | to negate a symbol we lookup the symbol and negate it in the store,
-- | possible creating a new symbolic reference if needed
Δ-negate : Δ → Symbolic → Δ × IL
Δ-negate st a@(sRef s) = Δ′ , (symIL ∘ sRef $ s′-ref)
  where
  s′ : Symbolic
  s′ = sNeg a

  s′-ref : Reference
  s′-ref = "¬" Data.String.++ s

  s′∈Δ : Bool
  s′∈Δ = any (s′-ref ==_) $ names st

  Δ′ : Δ
  Δ′ = if s′∈Δ then st else (s′-ref , s′) ∷ st

Δ-negate st s = st , symIL s

Δ-or : Δ → Symbolic → Symbolic → (Δ × IL)
Δ-or st l@(sRef s₁) r@(sRef s₂) = Δ′ , symIL s
  where
  s-ref : Reference
  s-ref =  s₁ Data.String.++ "∨" Data.String.++ s₂

  s : Symbolic
  s = sOr l r

  s∈Δ : Bool
  s∈Δ = any (s-ref ==_) $ names st

  Δ′ : Δ
  Δ′ = if s∈Δ then st else (s-ref , s) ∷ st
Δ-or st l r = st , orIL (symIL l) (symIL r)

-- | accumulation
data _↦_  : (Δ × IL) → (Δ × IL) → Set where

  acc-unit : ∀ {Δ}
    ----------------
    → (Δ , ●) ↦ (Δ , ●)

  acc-gen : ∀ {r Δ}
    → r ∉ (names Δ)
    ----------------------
    → (Δ , refIL r) ↦ Δ-spawn Δ r

  acc-ref : ∀ {store : Δ} {r : Reference}
    → { name∈store : True (r ∈? (names store)) }
    ---------------------
    → (store , refIL r) ↦ Δ-ref {store} {r} {name∈store}

  acc-neg : ∀ {s Δ}
    ----------------------
    → (Δ , symIL s) ↦ Δ-negate Δ s

  acc-C : ∀ {d l r Δ}
    ----------------------
    → (Δ , chcIL d l r) ↦ (Δ , chcIL d l r)

  acc-Neg-C : ∀ {d l r Δ}
    ----------------------
    → (Δ , negIL (chcIL d l r)) ↦ (Δ , chcIL d (vNeg l) (vNeg r)) -- notice negation is translated back to VPL

  acc-SOr : ∀ {l r Δ}
    ----------------------
    → (Δ , orIL (symIL l) (symIL r)) ↦ Δ-or Δ l r

-- TODO: Move accumulation to its own subdirectory
-- TODO: module for judgements and testing
-- TODO: do SAnd then congruence cases