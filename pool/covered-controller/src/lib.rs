//! Blent Covered Pool access controller.
//!
//! A BLNT v3 pool and its backstop ask a pool's access controller for a
//! user's permission bits:
//!
//!   bit 0  RESERVE_SUPPLY_ALLOWED    (pool/src/access.rs)
//!   bit 1  RESERVE_BORROW_ALLOWED    (pool/src/access.rs)
//!   bit 2  BACKSTOP_DEPOSIT_ALLOWED  (backstop/src/access.rs)
//!
//! This controller opens supply and borrow to everyone (3) and gives
//! backstop deposit only to addresses the admin has allowlisted (7).
//! The `pool` argument is ignored: the controller is deployed before the
//! pool, so it can't know the pool's address.
//!
//! Admin is the Blent Cover Reserve Fund's 2-of-3 classic multisig, set
//! once in the constructor.  There is no admin transfer: the fund rotates
//! its own signers on the classic account.  There is no upgrade function,
//! so this code is final.
//!
//! Removing a depositor makes them eligible for the backstop's
//! permissionless forced queue-for-withdrawal.  Supply/borrow are never
//! revoked, so no pool user can be forced out.  Withdraw, repay and Q4W
//! never call the controller.

#![no_std]

use soroban_sdk::{contract, contracterror, contractevent, contractimpl, contracttype, panic_with_error, Address, Env};

pub const RESERVE_SUPPLY_ALLOWED: u32 = 1 << 0;
pub const RESERVE_BORROW_ALLOWED: u32 = 1 << 1;
pub const BACKSTOP_DEPOSIT_ALLOWED: u32 = 1 << 2;

pub const OPEN: u32 = RESERVE_SUPPLY_ALLOWED | RESERVE_BORROW_ALLOWED;
pub const DEPOSITOR: u32 = OPEN | BACKSTOP_DEPOSIT_ALLOWED;

const LEDGERS_PER_DAY: u32 = 17_280;
/// Extend TTLs to ~120 days whenever they fall under ~30 days.
const TTL_THRESHOLD: u32 = 30 * LEDGERS_PER_DAY;
const TTL_EXTEND_TO: u32 = 120 * LEDGERS_PER_DAY;

#[contracttype]
#[derive(Clone)]
enum Key {
    Admin,
    Depositor(Address),
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum ControllerError {
    NoChange = 1,
}

#[contractevent(topics = ["set_backstop_depositor"], data_format = "single-value")]
struct SetBackstopDepositor {
    #[topic]
    user: Address,
    allowed: bool,
}

#[contract]
pub struct CoveredController;

fn bump_instance(e: &Env) {
    e.storage().instance().extend_ttl(TTL_THRESHOLD, TTL_EXTEND_TO);
}

#[contractimpl]
impl CoveredController {
    pub fn __constructor(e: Env, admin: Address) {
        e.storage().instance().set(&Key::Admin, &admin);
        bump_instance(&e);
    }

    /// Permission bits for `user`.  `pool` is ignored.
    pub fn permissions(e: Env, pool: Address, user: Address) -> u32 {
        let _ = pool;
        bump_instance(&e);
        let key = Key::Depositor(user);
        if e.storage().persistent().has(&key) {
            e.storage().persistent().extend_ttl(&key, TTL_THRESHOLD, TTL_EXTEND_TO);
            DEPOSITOR
        } else {
            OPEN
        }
    }

    /// Admin only.  Add (`allowed` = true) or remove a backstop depositor.
    /// Fails with NoChange if the user is already in that state, so a
    /// mistyped address or repeated call is visible.
    pub fn set_backstop_depositor(e: Env, user: Address, allowed: bool) {
        Self::admin(e.clone()).require_auth();
        bump_instance(&e);
        let key = Key::Depositor(user.clone());
        let store = e.storage().persistent();
        if store.has(&key) == allowed {
            panic_with_error!(&e, ControllerError::NoChange);
        }
        if allowed {
            store.set(&key, &());
            store.extend_ttl(&key, TTL_THRESHOLD, TTL_EXTEND_TO);
        } else {
            store.remove(&key);
        }
        SetBackstopDepositor { user, allowed }.publish(&e);
    }

    pub fn admin(e: Env) -> Address {
        e.storage().instance().get(&Key::Admin).unwrap()
    }

    pub fn is_backstop_depositor(e: Env, user: Address) -> bool {
        e.storage().persistent().has(&Key::Depositor(user))
    }
}

#[cfg(test)]
mod test;
