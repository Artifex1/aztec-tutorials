use dep::aztec::macros::aztec;

#[aztec]
contract Crowdfunding {
    use dep::aztec::{
        encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
        macros::{
            events::event,
            functions::{initializer, internal, private, public},
            storage::storage,
        },
        prelude::{AztecAddress, PrivateSet, PublicImmutable},
        protocol_types::traits::Serialize,
        unencrypted_logs::unencrypted_event_emission::encode_event,
        utils::comparison::Comparator,
    };
    use std::meta::derive;
    use dep::value_note::value_note::ValueNote;
    use router::utils::privately_check_timestamp;
    use token::Token;

    #[derive(Serialize)]
    #[event]
    struct WithdrawalProcessed {
        who: AztecAddress,
        amount: U128,
    }

    #[storage]
    struct Storage<Context> {
        // Token used for donations (e.g. DAI)
        donation_token: PublicImmutable<AztecAddress, Context>,
        // Crowdfunding campaign operator
        operator: PublicImmutable<AztecAddress, Context>,
        // End of the crowdfunding campaign after which no more donations are accepted
        deadline: PublicImmutable<u64, Context>,
        // Notes emitted to donors when they donate (can be used as proof to obtain rewards, eg in Claim contracts)
        donation_receipts: PrivateSet<ValueNote, Context>,
    }

    #[public]
    #[initializer]
    fn init(donation_token: AztecAddress, operator: AztecAddress, deadline: u64) {
        storage.donation_token.initialize(donation_token);
        storage.operator.initialize(operator);
        storage.deadline.initialize(deadline);
    }

    #[private]
    fn donate(amount: U128) {
        // 1) Check that the deadline has not passed --> we do that via the router contract to conceal which contract
        // is performing the check.
        let deadline = storage.deadline.read();
        privately_check_timestamp(Comparator.LT, deadline, &mut context);
        // 2) Transfer the donation tokens from donor to this contract
        let donor = context.msg_sender();
        Token::at(storage.donation_token.read())
            .transfer_in_private(donor, context.this_address(), amount, 0)
            .call(&mut context);
        // 3) Create a value note for the donor so that he can later on claim a rewards token in the Claim
        // contract by proving that the hash of this note exists in the note hash tree.
        // TODO(benesjan): Instead of ValueNote use UintNote to avoid the conversion to a Field below.
        let mut note = ValueNote::new(amount.to_field(), donor);

        storage.donation_receipts.insert(&mut note).emit(encode_and_encrypt_note(
            &mut context,
            donor,
            donor,
        ));
    }

    // Withdraws balance to the operator. Requires that msg_sender() is the operator.
    #[private]
    fn withdraw(amount: U128) {
        // 1) Check that msg_sender() is the operator
        let operator_address = storage.operator.read();
        assert(context.msg_sender() == operator_address, "Not an operator");

        // 2) Transfer the donation tokens from this contract to the operator
        Token::at(storage.donation_token.read()).transfer(operator_address, amount).call(
            &mut context,
        );

        // 3) Emit a public event so that anyone can audit how much the operator has withdrawn
        Crowdfunding::at(context.this_address())
            ._publish_donation_receipts(amount, operator_address)
            .enqueue(&mut context);
    }

    #[public]
    #[internal]
    fn _publish_donation_receipts(amount: U128, to: AztecAddress) {
        WithdrawalProcessed { amount, who: to }.emit(encode_event(&mut context));
    }

}

use token::Token;
use dep::aztec::test::helpers::test_environment::TestEnvironment;
use dep::aztec::prelude::AztecAddress;

#[test]
unconstrained fn test_donate() {
    let mut env = TestEnvironment::new();
    let admin = env.create_account();
    
    // deploy token
    let name: str<31>   = "Test000000000000000000000000000";
    let symbol: str<31> = "TST0000000000000000000000000000";
    let init_token = Token::interface().constructor(
        admin, name, symbol, 18
    );
    let token_instance = env.deploy("./@token_contract", "Token").with_public_void_initializer(init_token);
    /*
    let token_address = token_instance.to_address();
    // deploy crowdfunding
    let init_crowdfunding = Crowdfunding::interface().init(
        token_address, admin, 1337
    );
    let cf_instance = env.deploy_self("Crowdfunding").with_public_void_initializer(init_crowdfunding);
    let cf_address = cf_instance.to_address();

    (env, token_address, cf_address, admin) */
    /*
    let (mut env, token, crowdfunding, admin) = setup();
    let donor = env.create_account();

    env.impersonate(admin);
    Token::at(token).mint_to_public(donor, U128::from_integer(50)).call(&mut env.public());

    env.impersonate(donor);
    Crowdfunding::at(crowdfunding).donate(U128::from_integer(25)).call(&mut env.private());
    */
}
