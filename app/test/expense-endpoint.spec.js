const knex = require('knex')
const app = require('../src/app')
const helpers = require('./test-helpers')

describe('Expense Endpoint', function() {
    let db 

    const {testUsers, testExpenses} = helpers.makeFixtures()
    before('make knex instance', () => {
        db = knex({
            client: 'pg',
            connection: process.env.TEST_DATABASE_URL
        });
        app.set('db', db);
        
    })

    after('disconnect from db', () => db.destroy())

    before("cleanup", () => helpers.cleanTables(db));

    beforeEach('insert Expenses', () => {
        helpers.seedUsersTable(db, testUsers)
        helpers.seedExpenseTable(db, testExpenses)
    })

    afterEach('cleanup', () => helpers.cleanTables(db))

    describe('GET /api/expenses', () => {
        context('Given there are products in the database', () => {

            it('responds with 200 and all users expenses', () => {
                const expectedExpenses = helpers.makeExpectedUserExpenses(testUsers[0], testExpenses)
                const makeExpExpenses = expectedExpenses.map(expense => helpers.makeExpectedExpense(expense))
                return supertest(app)
                    .get('/api/expenses')
                    .set('Authorization', helpers.makeAuthHeader(testUsers[0]))
                    .expect(200, makeExpExpenses)
            })
        })
    })
    describe('DELETE /api/expenses/:expenseId', () => {
        context('delete expense', () => {
            
            it('deletes expense', () => {
                const expenseId = 4;
                return supertest(app)
                    .delete(`/api/expenses/${expenseId}`)
                    .set('Authorization', helpers.makeAuthHeader(testUsers[1]))
                    .expect(200)
            })

        })
    })
    describe('POST /api/expense', () => {
        
        const newExpense = {
            expense: '2.94',
            description: 'New Expense',
            user_id: testUsers[0].id,
        }
        it('inserts new expense', () => {
            return supertest(app)
                .post('/api/expenses')
                .send(newExpense)
                .set('Authorization', helpers.makeAuthHeader(testUsers[0]))
                .expect(201)
                .expect(res => {
                    expect(res.body).to.have.property('id')
                    expect(res.body.expense).to.eql(newExpense.expense)
                    expect(res.body.description).to.eql(newExpense.description)
                    expect(res.body.user_id).to.eql(testUsers[0].id)
                    expect(res.headers.location).to.eql(`/api/expenses/${res.body.id}`)
                    const expectedDate = new Date().toLocaleString('en', { timeZone: 'UTC' })
                    const actualDate = new Date(res.body.date_created).toLocaleString()
                    expect(actualDate).to.eql(expectedDate)
                })
                .expect(res =>
                    db
                        .from('expense')
                        .select('*')
                        .where({ id: res.body.id })
                        .first()
                        .then(row => {
                            expect(row.description).to.eql(newExpense.description)
                            expect(row.expense).to.eql(newExpense.expense)
                            expect(row.user_id).to.eql(newExpense.user_id)
                            const expectedDate = new Date().toLocaleString('en', { timeZone: 'UTC' })
                            const actualDate = new Date(row.date_created).toLocaleString()
                            expect(actualDate).to.eql(expectedDate)
                        })
                )
        })
    })
})