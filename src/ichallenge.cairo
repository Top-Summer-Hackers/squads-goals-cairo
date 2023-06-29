use core::result::ResultTrait;
use starknet::ContractAddress;
use starknet::contract_address_try_from_felt252;

#[abi]
trait IChallenge {
    // #[external]
    // fn initialize(
    //     stakeAmount: u256,
    //     maxAmountOfStakers: u256,
    //     duration: u256, //rewardNFTAddrr: ContractAddress,
    //     creator: ContractAddress
    // ) -> bool;
    #[external]
    fn join(name: felt252, _stakeAmount: u256) -> bool;
    #[view]
    fn completed() -> bool;
    #[view]
    fn stakeAmount() -> u256;
    #[view]
    fn maxAmountOfStakers() -> u256;
    #[view]
    fn deadline() -> u256;
    #[view]
    fn stakerCount() -> u256;
    #[view]
    fn votedCount() -> u256;
    //todo getStakers
    #[view]
    fn onVoting() -> u256;
}
