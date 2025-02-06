// @ts-ignore
export {};

import { DefaultAccountContract } from '@aztec/accounts/defaults';
import {
    AccountManager,
    AuthWitness,
    type AuthWitnessProvider,
    type CompleteAddress,
    Fr,
    GrumpkinScalar,
    Schnorr,
    createPXEClient,
    createLogger,
} from '@aztec/aztec.js';
import { SchnorrHardcodedAccountContractArtifact } from '@aztec/noir-contracts.js/SchnorrHardcodedAccount';
import { TokenContract } from '@aztec/noir-contracts.js/Token';
import { describe, it } from 'mocha';
import { expect } from 'chai';

// docs:start:account-contract
const PRIVATE_KEY = GrumpkinScalar.fromHexString('0xd35d743ac0dfe3d6dbe6be8c877cb524a00ab1e3d52d7bada095dfc8894ccfa');
const { PXE_URL = 'http://localhost:8080' } = process.env;

/** Account contract implementation that authenticates txs using Schnorr signatures. */
class SchnorrHardcodedKeyAccountContract extends DefaultAccountContract {
    constructor(private privateKey = PRIVATE_KEY) {
        super(SchnorrHardcodedAccountContractArtifact);
    }

    getDeploymentArgs() {
        // This contract has no constructor
        return Promise.resolve(undefined);
    }

    getAuthWitnessProvider(_address: CompleteAddress): AuthWitnessProvider {
        const privateKey = this.privateKey;
        return {
            async createAuthWit(messageHash: Fr): Promise<AuthWitness> {
                const signer = new Schnorr();
                const signature = await signer.constructSignature(messageHash.toBuffer(), privateKey);
                return Promise.resolve(new AuthWitness(messageHash, [...signature.toBuffer()]));
            },
        };
    }
}
// docs:end:account-contract

describe('writing_an_account_contract', function () {
    this.timeout(100000);

    it('works', async () => {
        const pxe = await createPXEClient(PXE_URL);
        // const { l1ChainId } = await pxe.getNodeInfo();
        const logger = createLogger('aztec:example');

        const secretKey = Fr.random();
        const account = await AccountManager.create(pxe, secretKey, new SchnorrHardcodedKeyAccountContract());
        const wallet = await account.waitSetup();
        const address = wallet.getCompleteAddress().address;
        logger.info(`Deployed account contract at ${address}`);

        const token = await TokenContract.deploy(wallet, address, 'TokenName', 'TokenSymbol', 18).send().deployed();
        logger.info(`Deployed token contract at ${token.address}`);

        const mintAmount = 50n;
        const from = address; // we are setting from to address here because of TODO(#9887)
        await token.methods.mint_to_private(from, address, mintAmount).send().wait();

        const balance = await token.methods.balance_of_private(address).simulate();
        logger.info(`Balance of wallet is now ${balance}`);

        expect(balance).to.equal(50n);
        const wrongKey = GrumpkinScalar.random();
        const wrongAccountContract = new SchnorrHardcodedKeyAccountContract(wrongKey);
        const wrongAccount = await AccountManager.create(pxe, secretKey, wrongAccountContract, account.salt);
        const wrongWallet = await wrongAccount.getWallet();
        const tokenWithWrongWallet = token.withWallet(wrongWallet);
        logger.info("GETTING HERE");

        try {
            await tokenWithWrongWallet.methods.mint_to_public(address, 200).prove();
            expect(false);
        } catch (err) {
            expect(true);
        }
    });
});
