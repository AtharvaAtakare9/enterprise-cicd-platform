const bcrypt = require('bcryptjs')
const jwt = require('jsonwebtoken')

function makeUserArray() {
    return [
        {
            id: 1,
            full_name: "Test User 1",
            username: "TestUser1",
            email_address: "thisemail@google.com",
            password: "GreatPassword1!",
            date_created: new Date("2029-01-22T16:28:32.615Z")
        },
        {
            id: 2,
            full_name: "Test User 2",
            email_address: "thatemail@google.com",
            username: "TestUser2",
            password: "GreatPassword2!",
            date_created: new Date("2029-02-22T16:28:32.615Z")
        },
        {
            id: 3,
            full_name: "Test User 3",
            email_address: "thereemail@google.com",
            username: "TestUser3",
            password: "GreatPassword3!",
            date_created: new Date("2029-03-22T16:28:32.615Z")
        },
        {
            id: 4,
            full_name: "Test User 4",
            email_address: "thenemail@google.com",
            username: "TestUser4",
            password: "GreatPassword4!",
            date_created: new Date("2029-04-22T16:28:32.615Z")
        }
    ];
}

function makeExpensesArray() {
    return [
        {
            id: 1,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 1
        },
        {
            id: 2,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 1
        },
        {
            id: 3,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 2
        },
        {
            id: 4,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 2
        },
        {
            id: 5,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 1
        },
        {
            id: 6,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 1
        },
        {
            id: 7,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 2
        },
        {
            id: 8,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 2
        },
        {
            id: 9,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 3
        },
        {
            id: 10,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 3
        },
        {
            id: 11,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 4
        },
        {
            id: 12,
            expense: '2.93',
            description: 'Expense',
            date_created: new Date("2029-01-22T16:28:32.615Z"),
            user_id: 4
        },
    ]
}

function cleanTables(db) {
    return db.transaction(trx => 
            trx
                .raw(
                    `TRUNCATE
                    expense,
                    users`
                )
                .then(() =>
                    Promise.all([
                        trx.raw(
                            `ALTER SEQUENCE users_id_seq minvalue 0 START WITH 1`
                        ),
                        trx.raw(
                            `ALTER SEQUENCE expense_id_seq minvalue 0 START WITH 1`
                        ),
                        trx.raw(`SELECT setval('users_id_seq', 0)`),
                        trx.raw(`SELECT setval('expense_id_seq', 0)`)
                    ])
                )
        )
}

function seedUsersTable(db, users) {
    const preppedUsers = users.map(user => ({
        ...user,
        password: bcrypt.hashSync(user.password, 1)
    }))
    return db.into('users').insert(preppedUsers)
        .then(() => {
            db.raw(
                `SELECT setval('users_id_seq', ?)`, [users[users.length - 1].id]
            )
        })
}

function seedExpenseTable(db, expenses) {
    return db.transaction(async trx => {
        
        await trx.into('expense').insert(expenses)
        await trx.raw(`SELECT setval('expense_id_seq', ?)`, [expenses[expenses.length - 1].id])
    })
}  

function makeAuthHeader(user, secret = process.env.JWT_SECRET) {
    const token = jwt.sign({ user_id: user.id, username: user.username }, secret, {
        subject: user.username,
        algorithm: 'HS256'
    })
    
    return `Bearer ${token}`

}

function makeFixtures() {
    const testUsers = makeUserArray()
    const testExpenses = makeExpensesArray()
    
    return { testUsers, testExpenses } 
}

function makeExpectedUserExpenses(user, expenses) {
    const expectedExpense = expenses.filter(expense => expense.user_id === user.id)
    return expectedExpense
}

function makeExpectedExpense(expense) {
    return {
        id: expense.id,
        expense: expense.expense,
        description: expense.description,
        date_created: expense.date_created.toISOString(),
        user_id: expense.user_id
    }
}

module.exports = {
    makeUserArray,
    makeExpensesArray,
    cleanTables,
    seedUsersTable,
    seedExpenseTable,
    makeAuthHeader,
    makeFixtures,
    makeExpectedExpense,
    makeExpectedUserExpenses
}