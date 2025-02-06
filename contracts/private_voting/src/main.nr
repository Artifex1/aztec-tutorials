// docs:start:declaration
use dep::aztec::macros::aztec;

#[aztec]
contract EasyPrivateVoting {

    use dep::aztec::{
        keys::getters::get_public_keys,
        macros::{functions::{initializer, internal, private, public}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable}
    };

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>, // admin can end vote
        tally: Map<Field, PublicMutable<Field, Context>, Context>, // we will store candidate as key and number of votes as value
        vote_ended: PublicMutable<bool, Context>, // vote_ended is boolean
        active_at_block: PublicImmutable<u32, Context>, // when people can start voting
    }
    
    #[public]
    #[initializer]
    // annotation to mark function as a constructor
    fn constructor(admin: AztecAddress) {
        storage.admin.write(admin);
        storage.vote_ended.write(false);
        storage.active_at_block.initialize(context.block_number() as u32);
    }
    
    #[private]
    // annotation to mark function as private and expose private context
    fn cast_vote(candidate: Field) {
        let msg_sender_npk_m_hash = get_public_keys(context.msg_sender()).npk_m.hash();

        let secret = context.request_nsk_app(msg_sender_npk_m_hash); // get secret key of caller of function
        let nullifier = std::hash::pedersen_hash([context.msg_sender().to_field(), secret]); // derive nullifier from sender and secret
        context.push_nullifier(nullifier);
        EasyPrivateVoting::at(context.this_address()).add_to_tally_public(candidate).enqueue(
            &mut context,
        );
    }
    
    #[public]
    #[internal]
    fn add_to_tally_public(candidate: Field) {
        assert(storage.vote_ended.read() == false, "Vote has ended"); // assert that vote has not ended
        let new_tally = storage.tally.at(candidate).read() + 1;
        storage.tally.at(candidate).write(new_tally);
    }
    
    #[public]
    fn end_vote() {
        assert(storage.admin.read().eq(context.msg_sender()), "Only admin can end votes"); // assert that caller is admin
        storage.vote_ended.write(true);
    }
    
    pub unconstrained fn get_vote(candidate: Field) -> pub Field {
        storage.tally.at(candidate).read()
    }
}

// test imports
use dep::aztec::test::helpers::test_environment::TestEnvironment;
use dep::aztec::context::call_interfaces::PublicVoidCallInterface;
use dep::aztec::prelude::AztecAddress;
use dep::aztec::protocol_types::storage::map::derive_storage_slot_in_map;
use dep::aztec::oracle::{execution::get_block_number, storage::storage_read};


unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_account();
    
    // setup EasyPrivateVoting
    let init: PublicVoidCallInterface<11> = EasyPrivateVoting::interface().constructor(admin);
    let voting_instance = env.deploy_self("EasyPrivateVoting").with_public_void_initializer(init);
    let voting_address = voting_instance.to_address();

    (env, voting_address, admin)
}

#[test]
unconstrained fn test_vote() {
    let (mut env, voting_address, _) = setup();
    
    let voter = env.create_account();
    let candidate = 1;

    // vote
    env.impersonate(voter);
    EasyPrivateVoting::at(voting_address).cast_vote(candidate).call(&mut env.private());
    
    // check storage
    let block_number = get_block_number();
    let tally_slot = EasyPrivateVoting::storage_layout().tally.slot;
    let candidate_tally_slot = derive_storage_slot_in_map(tally_slot, candidate);
    let vote_count: u32 = storage_read(voting_address, candidate_tally_slot, block_number);

    assert(vote_count == 1);
}

#[test]
unconstrained fn test_end_vote() {
    let (mut env, voting_address, admin) = setup();

    env.impersonate(admin);
    EasyPrivateVoting::at(voting_address).end_vote().call(&mut env.public());
    let vote_ended_slot = EasyPrivateVoting::storage_layout().vote_ended.slot;
    let current_vote_ended = storage_read(voting_address, vote_ended_slot, get_block_number());

    assert(current_vote_ended == true, "Vote not ended as expected");

    // check that voting now fails
    let user = env.create_account();
    env.impersonate(user);
    let cast_vote = EasyPrivateVoting::at(voting_address).end_vote();
    env.assert_private_call_fails(cast_vote);
}

#[test(should_fail)]
unconstrained fn test_no_double_voting() {
    let (mut env, voting_address, admin) = setup();
    let user = env.create_account();

    env.impersonate(user);
    EasyPrivateVoting::at(voting_address).end_vote().call(&mut env.public());
    EasyPrivateVoting::at(voting_address).end_vote().call(&mut env.public());
}
