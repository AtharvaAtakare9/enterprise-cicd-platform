const knex = require('knex')
const jwt = require('jsonwebtoken')
const app = require('../src/app')
const helpers = require('./test-helpers')

describe('Auth Endpoint', function() {
    let db

    const { testUsers } = helpers.makeFixtures()
    const testUser = testUsers[0]

    before('make knex instance', () => {
        db = knex({
            client: 'pg',
            connection: process.env.TEST_DATABASE_URL
        })
        app.set('db', db)
    })

    after('disconnect from db', () => db.destroy())

    before('cleanup', () => helpers.cleanTables(db))

    afterEach('cleanup', () => helpers.cleanTables(db))

    describe('POST /api/auth/login', () => {
        beforeEach('insert users', () => {
            helpers.seedUsersTable(db, testUsers)
        })

        const requiredFields = ['username', 'password']

        requiredFields.forEach(field => {
            const loginAttemptBody = {
                username: testUser.username,
                password: testUser.password
            }
        })
        it(`responds 200 and JWT auth token using secret when valid creds`, () => {
            const userValidCreds = {
                username: testUser.username,
                password: testUser.password
            };
            const expectedToken = jwt.sign(
                { user_id: testUser.id, username: testUser.username }, //payload
                process.env.JWT_SECRET,
                {
                    subject: testUser.username,
                    expiresIn: process.env.JWT_EXPIRY,
                    algorithm: "HS256"
                }
            );
            return supertest(app)
                .post("/api/auth/login")
                .send(userValidCreds)
                .expect(200, {
                    authToken: expectedToken,
                    userId: testUser.id
                });
        });
    })
})