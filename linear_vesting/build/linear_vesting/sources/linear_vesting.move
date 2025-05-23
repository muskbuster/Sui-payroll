module linea_vesting::linear_vesting {
    // === Imports ===

    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::transfer;

    // === Errors ===

    // @dev Error code for invalid start date
    const EInvalidStartDate: u64 = 0;

    // === Structs ===

    // Wallet struct
    public struct Wallet<phantom T> has key, store {
        id: UID,
        // Balance of the wallet
        balance: Balance<T>,
        // Start date of the claiming
        start: u64,
        // Total amount of Coin released
        released: u64,
        // Duration of the vesting
        duration: u64
    }

    // === Public-Mutative Functions ===

    /*
    * @notice Creates a new Wallet with the given token, start date, duration and context
    *
    * @param token: Coin<T> - The token to be vested
    * @param c: &Clock - The clock to get the current timestamp
    * @param start: u64 - The start date of the vesting
    * @param duration: u64 - The duration of the vesting
    * @param ctx: &mut TxContext - The transaction context
    *
    * @return Wallet<T> - The new Wallet
    */
    public fun new<T>(token: Coin<T>, c: &Clock, start: u64, duration: u64, ctx: &mut TxContext): Wallet<T> {
        assert!(start >= clock::timestamp_ms(c), EInvalidStartDate);
            Wallet {
            id: object::new(ctx),
            balance: coin::into_balance(token),
            released: 0,
            start, 
            duration,
        }
    }

    /*
    * @notice The entry point to create a new Wallet with the given token, start date, duration and receiver
    *
    * @param token: Coin<T> - The token to be vested
    * @param c: &Clock - The clock to get the current timestamp
    * @param start: u64 - The start date of the vesting
    * @param duration: u64 - The duration of the vesting
    * @param receiver: address - The address of the receiver
    * @param ctx: &mut TxContext - The transaction context
    */
    entry fun entry_new<T>(token: Coin<T>, c: &Clock, start: u64, duration: u64, receiver: address, ctx: &mut TxContext) {
        transfer::public_transfer(new(token, c, start, duration, ctx), receiver);
    }

    /*
    * @notice To check the status of the vesting
    *
    * @param self: &Wallet<T> - The wallet to check the status
    * @param c: &Clock - The clock to get the current timestamp
    *
    * @return u64 - The status of the vesting
    */
    public fun vesting_status<T>(self: &Wallet<T>, c: &Clock): u64 {
        linear_vested_amount(
            self.start, 
            self.duration, 
            balance::value(&self.balance), 
            self.released, 
            clock::timestamp_ms(c)
        ) - self.released
    }

    /*
    * @notice To claim the vested amount
    *
    * @param self: &mut Wallet<T> - The wallet to claim the vested amount
    * @param c: &Clock - The clock to get the current timestamp
    * @param ctx: &mut TxContext - The transaction context
    *
    * @return Coin<T> - The vested amount of Coin
    */
    public fun claim<T>(self: &mut Wallet<T>, c: &Clock, ctx: &mut TxContext): Coin<T> {
        let releasable = vesting_status(self, c);

        *&mut self.released = self.released + releasable;

        coin::from_balance(balance::split(&mut self.balance, releasable), ctx)
    }

    /*
    * @notice The entry point to claim the vested amount
    *
    * @param self: &mut Wallet<T> - The wallet to claim the vested amount
    * @param c: &Clock - The clock to get the current timestamp
    * @param ctx: &mut TxContext - The transaction context
    */
    entry fun entry_claim<T>(self: &mut Wallet<T>, c: &Clock, ctx: &mut TxContext) {
        transfer::public_transfer(claim(self, c, ctx), tx_context::sender(ctx));
    }

    /*
    * @notice To destroy the wallet when wallet has zero balance
    *
    * @param self: Wallet<T> - The wallet to destroy
    */
    public fun destroy_zero<T>(self: Wallet<T>) {
        let Wallet { id, start: _, duration: _, balance, released: _} = self;
        object::delete(id);
        balance::destroy_zero(balance);
    }

    /*
    * @notice The entry point to destroy the wallet when wallet has zero balance
    *
    * @param self: Wallet<T> - The wallet to destroy
    */
    entry fun entry_destroy_zero<T>(self: Wallet<T>) {
        destroy_zero(self);
    }

    // === Public-View Functions ===

    /*
    * @notice To get the balance of the wallet
    *
    * @param self: &Wallet<T> - The wallet to get the balance
    *
    * @return u64 - The balance of the wallet
    */
    public fun balance<T>(self: &Wallet<T>): u64 {
        balance::value(&self.balance)
    }

    /*
    * @notice To get the start date of the vesting
    *
    * @param self: &Wallet<T> - The wallet to get the start date
    *
    * @return u64 - The start date of the vesting
    */
    public fun start<T>(self: &Wallet<T>): u64 {
        self.start
    }  

    /*
    * @notice To get the released amount of Coin
    *
    * @param self: &Wallet<T> - The wallet to get the released amount
    *
    * @return u64 - The released amount of Coin
    */
    public fun released<T>(self: &Wallet<T>): u64 {
        self.released
    }

    /*
    * @notice To get the duration of the vesting
    *
    * @param self: &Wallet<T> - The wallet to get the duration
    *
    * @return u64 - The duration of the vesting
    */
    public fun duration<T>(self: &Wallet<T>): u64 {
        self.duration
    }  

    // === Private Functions ===

    /*
    * @notice To calculate the vested amount
    *
    * @param start: u64 - The start date of the vesting
    * @param duration: u64 - The duration of the vesting
    * @param balance: u64 - The balance of the wallet
    * @param already_released: u64 - The already released amount of Coin
    * @param timestamp: u64 - The current timestamp
    *
    * @return u64 - The vested amount
    */
    fun linear_vested_amount(start: u64, duration: u64, balance: u64, already_released: u64, timestamp: u64): u64 {
        linear_vesting_schedule(start, duration, balance + already_released, timestamp)
    }

    /*
    * @notice To calculate the vested amount based on the linear vesting schedule
    *
    * @param start: u64 - The start date of the vesting
    * @param duration: u64 - The duration of the vesting
    * @param total_allocation: u64 - The total allocation of Coin
    * @param timestamp: u64 - The current timestamp
    *
    * @return u64 - The vested amount
    */
    fun linear_vesting_schedule(start: u64, duration: u64, total_allocation: u64, timestamp: u64): u64 {
        if (timestamp < start) return 0;
        if (timestamp > start + duration) return total_allocation;
        (total_allocation * (timestamp - start)) / duration
    }   
}