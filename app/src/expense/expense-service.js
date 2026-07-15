const ExpenseService = {
    getAllExpenses(db) {
        return db.select('*').from('expense').orderBy('date_created', 'desc');
    },
    getUsersExpenses(db, id) {
        return db
            .select('*')
            .from('expense')
            .where('user_id', id)
            .orderBy('date_created', 'DESC');
    },
    insertExpense(db, newExpense) {
        return db
            .insert(newExpense)
            .into('expense')
            .returning('*')
            .then(rows => {
                return rows[0];
            });
    },
    getUserExpenseById(db, id, user_id) {
        return db
            .select('*')
            .from('expense')
            .where({id, user_id})
            .first();
    },
    getById(db, id) {
        return db
            .select('*')
            .from("expense")
            .where('id', id)
            .first();
    },
    updateExpense(db, id, newExpenseField) {
        return db('expense')
            .where({ id })
            .update(newExpenseField);
    },
    deleteExpense(db, id) {
        return db('expense')
            .where({ id })
            .delete();
    }
}

module.exports = ExpenseService