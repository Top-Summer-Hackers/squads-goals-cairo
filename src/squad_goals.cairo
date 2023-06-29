#[contract]
mod SquadGoals {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use array::ArrayTrait;

    struct ChallengeReturnData {
        challenge: ContractAddress,
        NFT: ContractAddress,
        stakeAmount: u256,
        maxAmount: u256,
        deadline: u256,
        stakerCount: u256,
    }
}
