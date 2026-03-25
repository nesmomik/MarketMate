import os
import pg8000.native

def handler(event, context):

    host = os.environ['DB_HOST']
    app_db = os.environ['APP_DB_NAME']
    app_user = os.environ['APP_DB_USER']
    app_pass = os.environ['APP_DB_PASS']

    try:
        # connect directly to the app database
        app_con = pg8000.native.Connection(
            user=app_user,
            password=app_pass,
            host=host,
            database=app_db
        )

        print(f"Seeding database {app_db}...")
        with open('sqlite_dump_clean.sql', 'r') as f:
            sql_commands = f.read()

        app_con.run(sql_commands)
        app_con.close()

        return {'statusCode': 200, 'body': 'Database seeded successfully.'}

    except Exception as e:
        print(f"ERROR: {str(e)}")
        raise e