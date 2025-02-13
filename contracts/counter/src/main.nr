// docs:start:setup
use dep::aztec::macros::aztec;

#[aztec]
contract Counter {
    
    use aztec::macros::{functions::{initializer, private}, storage::storage};
    use aztec::prelude::{AztecAddress, Map};
    use easy_private_state::EasyPrivateUint;
    use value_note::balance_utils;
    
    #[storage]
    struct Storage<Context> {
        counters: Map<AztecAddress, EasyPrivateUint<Context>, Context>,
    }
    
    #[initializer]
    #[private]
    // We can name our initializer anything we want as long as it's marked as aztec(initializer)
    fn initialize(headstart: u64, owner: AztecAddress) {
        let counters = storage.counters;
        counters.at(owner).add(headstart, owner, context.msg_sender());
    }
    
    #[private]
    fn increment(owner: AztecAddress, sender: AztecAddress) {
        unsafe {
            dep::aztec::oracle::debug_log::debug_log_format(
                "Incrementing counter for owner {0}",
                [owner.to_field()],
            );
        }
        let counters = storage.counters;
        counters.at(owner).add(1, owner, sender);
    }

    pub unconstrained fn get_counter(owner: AztecAddress) -> pub Field {
        let counters = storage.counters;
        balance_utils::get_balance(counters.at(owner).set)
    }
}

use dep::aztec::note::note_getter::{MAX_NOTES_PER_PAGE, view_notes};
use dep::aztec::note::note_viewer_options::NoteViewerOptions;
use value_note::value_note::ValueNote;

// use crate::test;
use dep::aztec::protocol_types::storage::map::derive_storage_slot_in_map;
use dep::aztec::test::helpers::test_environment::TestEnvironment;

#[test]
unconstrained fn test_counter() {
    let mut env = TestEnvironment::new();
    let owner = env.create_account(1);
    let sender = env.create_account(2);
    let initial_counter = 3;

    env.impersonate(owner);
    let initializer = Counter::interface().initialize(initial_counter, owner);
    let counter_contract = env.deploy_self("Counter").with_private_initializer(initializer);
    let contract_address = counter_contract.to_address();

    env.impersonate(contract_address);
    let counter_slot = Counter::storage_layout().counters.slot;
    let owner_slot = derive_storage_slot_in_map(counter_slot, owner);
    let mut options = NoteViewerOptions::new();
    let notes: BoundedVec<ValueNote, MAX_NOTES_PER_PAGE> = view_notes(owner_slot, options);
    let initial_note_value = notes.get(0).value;
    assert(initial_note_value as u64 == initial_counter, "Initialized value not as expected");

    Counter::at(contract_address).increment(owner, sender).call(&mut env.private());
    let current_value_for_owner = Counter::get_counter(owner);
    let expected_current_value = initial_counter + 1;
    assert(expected_current_value == current_value_for_owner as u64, "Counters don't match between expected and current");
}
