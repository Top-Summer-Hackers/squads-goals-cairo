#[contract]
mod Challenge {
    use squad_goals::IERC20;
    use squad_goals::IERC20::IERC20DispatcherTrait;
    use squad_goals::IERC20::IERC20Dispatcher;

    use starknet::StorageAccess;
    use starknet::contract_address_try_from_felt252;
    use starknet::StorageBaseAddress;
    use starknet::SyscallResult;
    use starknet::storage_read_syscall;
    use starknet::storage_write_syscall;
    use starknet::storage_address_from_base_and_offset;
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use array::ArrayTrait;

    ////////////////////////////////
    // constants
    ////////////////////////////////
    const CREATOR_FEE: u64 = 1000_u64;
    const PROTOCOL_FEE: u64 = 1000_u64;
    const STAKER_FEE: u64 = 8000_u64;
    const COOLDOWN_PERIOD: u64 = 259200; //3 * 24 * 60 * 60; 
    #[derive(Drop, Serde)]
    struct Staker {
        stakerAddress: ContractAddress,
        stakerName: felt252,
        upVotes: u64,
        downVotes: u64,
    }

    #[derive(Drop, Serde)]
    struct Vote {
        stakerAddr: ContractAddress,
        isUpvote: bool,
    }

    struct Storage {
        creator: ContractAddress,
        squadGoalsAddr: ContractAddress,
        //rewardNFTAddr: ContractAddress,
        stakeAmount: u256,
        maxAmountOfStakers: u32,
        deadline: u64, //todo use u256
        stakerCount: u32,
        votedCount: u256,
        stakers: LegacyMap::<ContractAddress, Staker>,
        stakersIds: LegacyMap::<u32, ContractAddress>,
        hasVoted: LegacyMap::<ContractAddress, bool>,
        hasVotedFor: LegacyMap::<(ContractAddress, ContractAddress), bool>,
        initialized: bool,
        completed: bool,
        pool_balance: u256,
    }

    impl StakerStorageAccess of StorageAccess<Staker> {
        fn write(
            address_domain: u32, base: StorageBaseAddress, value: Staker
        ) -> SyscallResult::<()> {
            storage_write_syscall(
                address_domain,
                storage_address_from_base_and_offset(base, 0_u8),
                value.stakerAddress.into()
            );

            storage_write_syscall(
                address_domain,
                storage_address_from_base_and_offset(base, 1_u8),
                value.stakerName.into()
            );

            storage_write_syscall(
                address_domain,
                storage_address_from_base_and_offset(base, 2_u8),
                value.upVotes.into()
            );
            storage_write_syscall(
                address_domain,
                storage_address_from_base_and_offset(base, 3_u8),
                value.downVotes.into()
            )
        }
        fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<Staker> {
            Result::Ok(
                Staker {
                    stakerAddress: contract_address_try_from_felt252(
                        storage_read_syscall(
                            address_domain, storage_address_from_base_and_offset(base, 0_u8)
                        )?
                    )
                        .expect('not ContractAddress'),
                    stakerName: storage_read_syscall(
                        address_domain, storage_address_from_base_and_offset(base, 1_u8)
                    )?,
                    upVotes: storage_read_syscall(
                        address_domain, storage_address_from_base_and_offset(base, 2_u8)
                    )?
                        .try_into()
                        .expect('not u64'),
                    downVotes: storage_read_syscall(
                        address_domain, storage_address_from_base_and_offset(base, 3_u8)
                    )?
                        .try_into()
                        .expect('not u64'),
                }
            )
        }
    }

    #[constructor]
    fn constructor(
        squadGoalsAddr: ContractAddress,
        //rewardNFTAddr: ContractAddress,
        stakeAmount: u256,
        maxAmountOfStakers: u32,
        duration: u64,
        creator: ContractAddress,
    ) {
        stakerCount::write(0_u32);
        votedCount::write(0_u256);
        initialized::write(false);
        completed::write(false);

        initializer(
            squadGoalsAddr, //rewardNFTAddr,
             stakeAmount, maxAmountOfStakers, duration, creator,
        );
        pool_balance::write(0_u256);
    }

    #[external]
    fn join(name: felt252, _stakeAmount: u256) {
        assert(!completed::read(), 'Challenge : Already completed');
        assert(get_block_timestamp() < deadline::read(), 'DeadlineHasPassed');
        assert(stakerCount::read() < maxAmountOfStakers::read(), 'MaxAmountOfStakersReached');
        assert(stakeAmount::read() != _stakeAmount, 'IncorrectAmountOfEthSent');
        assert(
            stakers::read(get_caller_address())
                .stakerAddress == contract_address_try_from_felt252(0)
                .unwrap(),
            'AlreadyJoined'
        );

        stakers::write(
            get_caller_address(),
            Staker {
                stakerAddress: get_caller_address(),
                stakerName: name,
                upVotes: 0_u64,
                downVotes: 0_u64,
            }
        );
        stakersIds::write(stakerCount::read(), get_caller_address());
        stakerCount::write(stakerCount::read() + 1_u32);
        pool_balance::write(pool_balance::read() + _stakeAmount);
    }

    #[external]
    fn submitVote(votes: Array<Vote>) {
        assert(!completed::read(), 'Challenge : Already completed');
        assert(
            stakers::read(get_caller_address())
                .stakerAddress != contract_address_try_from_felt252(0)
                .unwrap(),
            'Not Has Joined'
        );
        assert(stakerCount::read() >= 2, 'NotEnoughStakers');
        assert(hasVoted::read(get_caller_address()) == false, 'AlreadyVoted');
        assert(onVoting(), 'NoInCoolDownPeriod');
        assert(votes.len() == stakerCount::read(), 'IncorrectAmountOfVotes');

        let mut i: usize = 0;
        loop {
            if i > votes.len() - 1 {
                break ();
            }
            _checkAndVote(votes[i]);
            i += 1;
        };
        votedCount::write(votedCount::read() + 1_u256);
    }
    #[internal]
    fn initializer(
        squadGoalsAddr: ContractAddress,
        //rewardNFTAddr: ContractAddress,
        stakeAmount: u256,
        maxAmountOfStakers: u32,
        duration: u64,
        creator: ContractAddress,
    ) {
        assert(!initialized::read(), 'ContractAlreadyInitialized');
        initialized::write(true);
        //rewardNFTAddr::write(rewardNFTAddr);
        deadline::write(get_block_timestamp() + duration);
        stakeAmount::write(stakeAmount);
        maxAmountOfStakers::write(maxAmountOfStakers);
        squadGoalsAddr::write(squadGoalsAddr);
        creator::write(creator);
    }

    fn _checkAndVote(_vote: @Vote) {
        let caller = get_caller_address();
        assert(
            stakers::read(*_vote.stakerAddr)
                .stakerAddress != contract_address_try_from_felt252(0)
                .unwrap(),
            'Not Has Joined'
        );
        assert(hasVotedFor::read((caller, *_vote.stakerAddr)) == false, 'AlreadyVoted');
        assert(*_vote.stakerAddr != caller, 'InvalidVote'); //CannotVoteForSelf
        //todo: improve
        if *_vote.isUpvote {
            stakers::write(
                *_vote.stakerAddr,
                Staker {
                    stakerAddress: *_vote.stakerAddr,
                    stakerName: stakers::read(*_vote.stakerAddr).stakerName,
                    upVotes: stakers::read(*_vote.stakerAddr).upVotes + 1_u64,
                    downVotes: stakers::read(*_vote.stakerAddr).downVotes,
                }
            );
        } else {
            stakers::write(
                *_vote.stakerAddr,
                Staker {
                    stakerAddress: *_vote.stakerAddr,
                    stakerName: stakers::read(*_vote.stakerAddr).stakerName,
                    upVotes: stakers::read(*_vote.stakerAddr).upVotes,
                    downVotes: stakers::read(*_vote.stakerAddr).downVotes + 1_u64,
                }
            );
        }
        hasVotedFor::write((caller, *_vote.stakerAddr), true);
        hasVoted::write(caller, true);
    }

    #[external]
    fn executePayouts() {
        assert(!completed::read(), 'Challenge : Already completed');
        assert(get_block_timestamp() > deadline::read() + COOLDOWN_PERIOD, 'DeadlineHasNotPassed');
        assert(stakerCount::read() != 0, 'NotEnoughStakers');
        let this_contract = get_contract_address();
        if stakerCount::read() == 1 {
            IERC20Dispatcher {
                contract_address: this_contract
            }
                .transfer(
                    stakersIds::read(0), pool_balance::read()
                ); //todo this_contract.get_balance()
        }
    }


    fn onVoting() -> bool {
        get_block_timestamp() > deadline::read()
            & get_block_timestamp() < (deadline::read() + COOLDOWN_PERIOD)
    }
}

