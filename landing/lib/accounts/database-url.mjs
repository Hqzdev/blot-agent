export function accountDatabaseURL(environment = process.env) {
  return environment.BLOT_POSTGRES_URL || environment.DATABASE_URL;
}
