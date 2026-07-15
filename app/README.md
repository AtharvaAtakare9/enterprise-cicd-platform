<h1>Expense Tracker App</h1>

<p>This is an app to help track expenses. Users can register and login to track their expenses or login using the demo account.</p>

<a href="https://expense.moesprojects.com">Live Site</a>

<h2>Technologies Used</h2>

<ul>
  <li>React.js</li>
  <li>Node.js</li>
  <li>Postgresql</li>
</ul>

<h2>Launch</h2>

<ol>
  <li>Fork and clone the repo</li>
  <li>'npm install' in the directory</li>
  <li>create the database and run 'npm run migrate' in the database</li>
  <li>m start' or 'npm run dev' to start the server</li>
</ol>

<h2>Functionality</h2>

<p>The app uses GET requests to pull the expense information off the database. POST requests get sent to the database for adding expenses, logging a user in and creating a new user. DELETE requests are called when deleting an expense. In the future I would like to add in PATCH requests for both expenses and userss.</p>

<h3>Users</h3>

<p>For Posting and Getting user accounts</p>

```
{
  full_name: string,
  email_address: email,
  username: string,
  password: string
}
```

<h3>Expense</h3>

<p>For Posting, Getting and Deleting expenses</p>

```
For Posting, Getting and Deleting expenses
{
  expense: integer,
  description: string,
  user_id: integer,
  date_created: timestamp,
  id: integer
}
```

<h3>Auth</h3>

<p>For Posting to the Authentication of a user</p>

```
{
  username: string,
  password: string
}
```

<h3>API Overview</h3>

```
 /api
 .
 |-- /auth
 |    |__ POST
 |          |-- /login
 |-- /users
 |      |__ GET
 |           |-- /
 |      |__ POST
 |           |-- /
 |-- /expenses
 |       |__ GET
 |            |-- /
 |            |-- /:expense_id
 |       |__ POST
 |            |-- /
 |       |__ DELETE
 |            |-- /:expense_id
 ```
 
 <h3>POST</h3>
 
 ```
 /api/auth/login
 
 // req.body
 {
  username: string,
  password: string
}
// res.body
{
  authToken: string
}
```

<h3>GET</h3> 

```
/api/users

// res.body
{
  username: string,
  password: string,
  full_name: string,
  email_address: email
}
```

<h3>POST</h3> 

```
/api/users

// req.body
{
  username: string,
  password: string,
  full_name: string,
  email_address: email
}

//res.body
{
  username: string,
  password: string,
  full_name: string,
  email_address: email
}
```

<h3>POST</h3> 

```
/api/expenses

 // req.body
 {
  expense: integer,
  description: string,
  date_created: timestamp,
  id: integer,
  user_id: integer
}

// res.body
 {
  expense: integer,
  description: string,
  date_created: timestamp,
  id: integer,
  user_id: integer
}
```

<h3>GET</h3> 

```
/api/expenses

//res.body
{
  expense: integer,
  description: string,
  date_created: timestamp,
  id: integer,
  user_id: integer
}
```
 
<h2>Project Status</h2>

<p>This is a Minimal Viable Product (MVP)</p>

<h2>Landing Page</h2>

<img width="1680" alt="Screen Shot 2020-04-10 at 11 30 36 AM" src="https://user-images.githubusercontent.com/48130732/79013683-e3df5d80-7b2e-11ea-8449-d5a8cf48a19e.png">

<h2>Login Page</h2>

<img width="1680" alt="Screen Shot 2020-04-10 at 11 30 48 AM" src="https://user-images.githubusercontent.com/48130732/79013691-e5a92100-7b2e-11ea-9e8f-2fee9d991fdc.png">

<h2>Registration Page</h2>

<img width="1680" alt="Screen Shot 2020-04-10 at 11 30 59 AM" src="https://user-images.githubusercontent.com/48130732/79013694-e641b780-7b2e-11ea-8a40-1c2b6a3a452b.png">

<h2>Expenses Page</h2>

<img width="1680" alt="Screen Shot 2020-04-10 at 11 31 13 AM" src="https://user-images.githubusercontent.com/48130732/79013698-e772e480-7b2e-11ea-8174-edc1eb93abf5.png">
