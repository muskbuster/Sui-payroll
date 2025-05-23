module payroll::payroll {
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};
    use std::vector;

    // === Errors ===
    const EInvalidAmount: u64 = 0;
    const EInvalidEmployee: u64 = 1;
    const EInvalidPayroll: u64 = 2;
    const EInvalidPeriod: u64 = 3;
    const ENotAuthorized: u64 = 4;
    const EEmployeeExists: u64 = 5;
    const EEmployeeNotFound: u64 = 6;
    const EInvalidSalary: u64 = 7;
    const EInsufficientBalance: u64 = 8;

    // === Constants ===
    const PAYROLL_PERIOD_MONTHLY: u64 = 2592000000; // 30 days in milliseconds
    const PAYROLL_PERIOD_BIWEEKLY: u64 = 1209600000; // 14 days in milliseconds
    const PAYROLL_PERIOD_WEEKLY: u64 = 604800000; // 7 days in milliseconds

    // === Structs ===
    public struct Payroll<phantom T> has key, store {
        id: UID,
        // Total payroll budget
        budget: Balance<T>,
        // Payroll period in milliseconds
        period: u64,
        // Last payment timestamp
        last_payment: u64,
        // Payroll admin
        admin: address,
        // Employee table
        employees: Table<address, Employee<T>>,
        // Employee addresses for iteration
        employee_addresses: VecMap<address, bool>
    }

    public struct Employee<phantom T> has store {
        // Employee's salary
        salary: u64,
        // Employee's address
        address: address,
        // Last payment timestamp
        last_payment: u64,
        // Employee's status (true if active)
        is_active: bool
    }

    // === Events ===
    public struct PayrollCreated has copy, drop {
        payroll_id: address,
        admin: address,
        period: u64
    }

    public struct EmployeeAdded has copy, drop {
        employee_address: address,
        salary: u64
    }

    public struct EmployeeRemoved has copy, drop {
        employee_address: address
    }

    public struct SalaryUpdated has copy, drop {
        employee_address: address,
        old_salary: u64,
        new_salary: u64
    }

    public struct PaymentProcessed has copy, drop {
        employee_address: address,
        amount: u64,
        timestamp: u64
    }

    // === Functions ===
    public fun new_payroll<T>(
        budget: Coin<T>,
        period: u64,
        ctx: &mut TxContext
    ): Payroll<T> {
        assert!(period == PAYROLL_PERIOD_MONTHLY || 
                period == PAYROLL_PERIOD_BIWEEKLY || 
                period == PAYROLL_PERIOD_WEEKLY, 
                EInvalidPeriod);
        
        let total_amount = coin::value(&budget);
        assert!(total_amount > 0, EInvalidAmount);
        
        Payroll {
            id: object::new(ctx),
            budget: coin::into_balance(budget),
            period,
            last_payment: 0,
            admin: tx_context::sender(ctx),
            employees: table::new(ctx),
            employee_addresses: vec_map::empty()
        }
    }

    public fun add_employee<T>(
        payroll: &mut Payroll<T>,
        salary: u64,
        employee_address: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == payroll.admin, ENotAuthorized);
        assert!(!table::contains(&payroll.employees, employee_address), EEmployeeExists);
        assert!(salary > 0, EInvalidSalary);
        
        let employee = Employee {
            salary,
            address: employee_address,
            last_payment: 0,
            is_active: true
        };
        
        table::add(&mut payroll.employees, employee_address, employee);
        vec_map::insert(&mut payroll.employee_addresses, employee_address, true);
    }

    public fun remove_employee<T>(
        payroll: &mut Payroll<T>,
        employee_address: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == payroll.admin, ENotAuthorized);
        assert!(table::contains(&payroll.employees, employee_address), EEmployeeNotFound);
        
        let employee = table::borrow_mut(&mut payroll.employees, employee_address);
        employee.is_active = false;
        
        vec_map::remove(&mut payroll.employee_addresses, &employee_address);
    }

    public fun update_salary<T>(
        payroll: &mut Payroll<T>,
        employee_address: address,
        new_salary: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == payroll.admin, ENotAuthorized);
        assert!(table::contains(&payroll.employees, employee_address), EEmployeeNotFound);
        assert!(new_salary > 0, EInvalidSalary);
        
        let employee = table::borrow_mut(&mut payroll.employees, employee_address);
        let _old_salary = employee.salary; // Prefix with underscore to indicate intentionally unused
        employee.salary = new_salary;
    }

    public fun process_payment<T>(
        payroll: &mut Payroll<T>,
        employee_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(table::contains(&payroll.employees, employee_address), EEmployeeNotFound);
        
        let employee = table::borrow_mut(&mut payroll.employees, employee_address);
        assert!(employee.is_active, EInvalidEmployee);
        
        let payment_amount = employee.salary;
        assert!(balance::value(&payroll.budget) >= payment_amount, EInsufficientBalance);
        
        coin::from_balance(balance::split(&mut payroll.budget, payment_amount), ctx)
    }

    public fun process_all_payments<T>(
        payroll: &mut Payroll<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == payroll.admin, ENotAuthorized);
        
        let mut i = 0;
        let addresses = vec_map::keys(&payroll.employee_addresses);
        let len = vector::length(&addresses);
        
        while (i < len) {
            let employee_address = vector::borrow(&addresses, i);
            let should_pay = if (table::contains(&payroll.employees, *employee_address)) {
                let employee = table::borrow(&payroll.employees, *employee_address);
                employee.is_active
            } else {
                false
            };
            if (should_pay) {
                let payment = process_payment(payroll, *employee_address, clock, ctx);
                transfer::public_transfer(payment, *employee_address);
            };
            i = i + 1;
        };
    }

    // === Entry Functions ===
    entry fun create_payroll<T>(
        budget: Coin<T>,
        period: u64,
        ctx: &mut TxContext
    ) {
        let payroll = new_payroll(budget, period, ctx);
        transfer::public_transfer(payroll, tx_context::sender(ctx));
    }

    entry fun add_employee_entry<T>(
        payroll: &mut Payroll<T>,
        salary: u64,
        employee_address: address,
        ctx: &mut TxContext
    ) {
        add_employee(payroll, salary, employee_address, ctx);
    }

    entry fun remove_employee_entry<T>(
        payroll: &mut Payroll<T>,
        employee_address: address,
        ctx: &mut TxContext
    ) {
        remove_employee(payroll, employee_address, ctx);
    }

    entry fun update_salary_entry<T>(
        payroll: &mut Payroll<T>,
        employee_address: address,
        new_salary: u64,
        ctx: &mut TxContext
    ) {
        update_salary(payroll, employee_address, new_salary, ctx);
    }

    entry fun process_payment_entry<T>(
        payroll: &mut Payroll<T>,
        employee_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let payment = process_payment(payroll, employee_address, clock, ctx);
        transfer::public_transfer(payment, employee_address);
    }

    entry fun process_all_payments_entry<T>(
        payroll: &mut Payroll<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        process_all_payments(payroll, clock, ctx);
    }

    // === View Functions ===
    public fun get_employee<T>(payroll: &Payroll<T>, employee_address: address): (u64, u64, bool) {
        assert!(table::contains(&payroll.employees, employee_address), EEmployeeNotFound);
        let employee = table::borrow(&payroll.employees, employee_address);
        (employee.salary, employee.last_payment, employee.is_active)
    }

    public fun get_payroll_info<T>(payroll: &Payroll<T>): (u64, u64, u64) {
        (balance::value(&payroll.budget), payroll.period, payroll.last_payment)
    }

    public fun get_employee_count<T>(payroll: &Payroll<T>): u64 {
        vec_map::size(&payroll.employee_addresses)
    }
} 