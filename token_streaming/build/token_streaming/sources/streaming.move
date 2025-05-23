module token_streaming::streaming {
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::transfer;

    // === Errors ===
    const EInvalidAmount: u64 = 0;
    const EInvalidStream: u64 = 1;
    const EInvalidWithdraw: u64 = 2;
    const EStreamEnded: u64 = 3;

    // === Structs ===
    public struct Stream<phantom T> has key, store {
        id: UID,
        // Total amount to be streamed
        total_amount: u64,
        // Amount withdrawn so far
        withdrawn_amount: u64,
        // Start time of the stream
        start_time: u64,
        // End time of the stream
        end_time: u64,
        // Recipient of the stream
        recipient: address,
        // Sender of the stream
        sender: address,
        // Balance of the stream
        balance: Balance<T>
    }

    // === Events ===
    public struct StreamCreated has copy, drop {
        stream_id: ID,
        sender: address,
        recipient: address,
        total_amount: u64,
        start_time: u64,
        end_time: u64
    }

    public struct StreamWithdrawn has copy, drop {
        stream_id: ID,
        amount: u64,
        recipient: address
    }

    public struct StreamCancelled has copy, drop {
        stream_id: ID,
        sender: address,
        recipient: address,
        sender_amount: u64,
        recipient_amount: u64
    }

    // === Functions ===
    public fun create_stream<T>(
        amount: Coin<T>,
        recipient: address,
        start_time: u64,
        end_time: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Stream<T> {
        // let current_time = clock::timestamp_ms(clock);
        // assert!(start_time >= current_time, EInvalidStream);
        // assert!(end_time > start_time, EInvalidStream);
        
        let total_amount = coin::value(&amount);
        assert!(total_amount > 0, EInvalidAmount);
        
        Stream {
            id: object::new(ctx),
            total_amount,
            withdrawn_amount: 0,
            start_time,
            end_time,
            recipient,
            sender: tx_context::sender(ctx),
            balance: coin::into_balance(amount)
        }
    }

    public fun withdraw<T>(
        stream: &mut Stream<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<T> {
        // let current_time = clock::timestamp_ms(clock);
        // assert!(current_time >= stream.start_time, EInvalidWithdraw);
        // assert!(current_time <= stream.end_time, EStreamEnded);
        assert!(tx_context::sender(ctx) == stream.recipient, EInvalidWithdraw);
        
        // let elapsed = current_time - stream.start_time;
        // let duration = stream.end_time - stream.start_time;
        // let total_withdrawable = (stream.total_amount * elapsed) / duration;
        // let withdrawable = total_withdrawable - stream.withdrawn_amount;
        let withdrawable = stream.total_amount - stream.withdrawn_amount;
        
        assert!(withdrawable > 0, EInvalidWithdraw);
        stream.withdrawn_amount = stream.withdrawn_amount + withdrawable;
        
        coin::from_balance(balance::split(&mut stream.balance, withdrawable), ctx)
    }

    public fun cancel_stream<T>(
        stream: Stream<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<T>) {
        // let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);
        assert!(sender == stream.sender || sender == stream.recipient, EInvalidStream);
        
        // let elapsed = if (current_time > stream.end_time) {
        //     stream.end_time - stream.start_time
        // } else {
        //     current_time - stream.start_time
        // };
        // let duration = stream.end_time - stream.start_time;
        // let total_withdrawable = (stream.total_amount * elapsed) / duration;
        // let recipient_amount = total_withdrawable - stream.withdrawn_amount;
        // let sender_amount = stream.total_amount - total_withdrawable;
        let recipient_amount = stream.total_amount - stream.withdrawn_amount;
        let sender_amount = 0;
        
        let Stream { id, mut balance, .. } = stream;
        object::delete(id);
        
        if (recipient_amount > 0 && sender_amount > 0) {
            let recipient_balance = balance::split(&mut balance, recipient_amount);
            (coin::from_balance(recipient_balance, ctx), coin::from_balance(balance, ctx))
        } else if (recipient_amount > 0) {
            (coin::from_balance(balance, ctx), coin::zero(ctx))
        } else {
            (coin::zero(ctx), coin::from_balance(balance, ctx))
        }
    }

    // === Entry Functions ===
    entry fun create_stream_entry<T>(
        amount: Coin<T>,
        recipient: address,
        start_time: u64,
        end_time: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let stream = create_stream(amount, recipient, start_time, end_time, clock, ctx);
        transfer::public_transfer(stream, recipient);
    }

    entry fun withdraw_entry<T>(
        stream: &mut Stream<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let amount = withdraw(stream, clock, ctx);
        transfer::public_transfer(amount, tx_context::sender(ctx));
    }

    entry fun cancel_stream_entry<T>(
        stream: Stream<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Store addresses before moving stream
        let recipient = stream.recipient;
        let sender = stream.sender;
        
        let (mut recipient_amount, mut sender_amount) = cancel_stream(stream, clock, ctx);
        
        // Transfer coins to respective addresses
        if (coin::value(&recipient_amount) > 0) {
            transfer::public_transfer(recipient_amount, recipient);
        } else {
            transfer::public_transfer(recipient_amount, tx_context::sender(ctx));
        };
        
        if (coin::value(&sender_amount) > 0) {
            transfer::public_transfer(sender_amount, sender);
        } else {
            transfer::public_transfer(sender_amount, tx_context::sender(ctx));
        };
    }
} 