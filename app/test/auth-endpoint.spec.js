const knex = require('knex');
const jwt = require('jsonwebtoken');
const supertest = require('supertest');
const app = require('../src/app');
const helpers = require('./test-helpers');

describe('Auth Endpoint', function () {
  let db;

  const { testUsers } = helpers.makeFixtures();
  const testUser = testUsers[0];

  before('make knex instance', () => {
    db = knex({
      client: 'pg',
      connection: process.env.TEST_DATABASE_URL,
    });

    app.set('db', db);
  });

  after('disconnect from db', () => db.destroy());

  before('cleanup', () => helpers.cleanTables(db));

  afterEach('cleanup', () => helpers.cleanTables(db));

  describe('POST /api/auth/login', () => {
    beforeEach('insert users', () => {
      return helpers.seedUsersTable(db, testUsers);
    });

    it('responds 200 and JWT auth token using secret when valid creds', () => {
      const userValidCreds = {
        username: testUser.username,
        password: testUser.password,
      };

      const expectedToken = jwt.sign(
        {
          user_id: testUser.id,
          username: testUser.username,
        },
        process.env.JWT_SECRET,
        {
          subject: testUser.username,
          expiresIn: process.env.JWT_EXPIRY,
          algorithm: 'HS256',
        }
      );

      return supertest(app)
        .post('/api/auth/login')
        .send(userValidCreds)
        .expect(200)
        .expect(res => {
          expect(res.body.userId).to.eql(testUser.id);
          expect(res.body.authToken).to.eql(expectedToken);
        });
    });
  });
});