extern crate std;

use soroban_sdk::{
    testutils::{Address as _, AuthorizedFunction, AuthorizedInvocation, Events},
    Address, Env, IntoVal, Symbol,
};

use crate::{CoveredController, CoveredControllerClient, DEPOSITOR, OPEN};

fn setup(e: &Env) -> (Address, CoveredControllerClient<'_>) {
    let admin = Address::generate(e);
    let id = e.register(CoveredController, (admin.clone(),));
    (admin, CoveredControllerClient::new(e, &id))
}

#[test]
fn everyone_can_supply_and_borrow() {
    let e = Env::default();
    let (_, c) = setup(&e);
    let pool = Address::generate(&e);
    let other_pool = Address::generate(&e);
    let user = Address::generate(&e);
    assert_eq!(OPEN, 3);
    assert_eq!(c.permissions(&pool, &user), 3);
    assert_eq!(c.permissions(&other_pool, &user), 3);
    assert!(!c.is_backstop_depositor(&user));
}

#[test]
fn admin_allowlists_and_removes_depositor() {
    let e = Env::default();
    e.mock_all_auths();
    let (admin, c) = setup(&e);
    let pool = Address::generate(&e);
    let user = Address::generate(&e);
    let stranger = Address::generate(&e);

    c.set_backstop_depositor(&user, &true);
    assert_eq!(
        e.auths()[0],
        (
            admin.clone(),
            AuthorizedInvocation {
                function: AuthorizedFunction::Contract((
                    c.address.clone(),
                    Symbol::new(&e, "set_backstop_depositor"),
                    (user.clone(), true).into_val(&e),
                )),
                sub_invocations: std::vec![],
            }
        )
    );
    assert_eq!(e.events().all().events().len(), 1);
    assert_eq!(DEPOSITOR, 7);
    assert_eq!(c.permissions(&pool, &user), 7);
    assert_eq!(c.permissions(&pool, &stranger), 3);
    assert!(c.is_backstop_depositor(&user));

    c.set_backstop_depositor(&user, &false);
    assert_eq!(c.permissions(&pool, &user), 3);
    assert!(!c.is_backstop_depositor(&user));
    assert_eq!(c.admin(), admin);
}

#[test]
#[should_panic(expected = "Error(Contract, #1)")]
fn repeated_add_fails() {
    let e = Env::default();
    e.mock_all_auths();
    let (_, c) = setup(&e);
    let user = Address::generate(&e);
    c.set_backstop_depositor(&user, &true);
    c.set_backstop_depositor(&user, &true);
}

#[test]
#[should_panic(expected = "Error(Contract, #1)")]
fn removing_unknown_fails() {
    let e = Env::default();
    e.mock_all_auths();
    let (_, c) = setup(&e);
    c.set_backstop_depositor(&Address::generate(&e), &false);
}

#[test]
#[should_panic]
fn non_admin_cannot_set() {
    let e = Env::default();
    let (_, c) = setup(&e);
    let user = Address::generate(&e);
    // no auth mocked: admin signature missing
    c.set_backstop_depositor(&user, &true);
}
