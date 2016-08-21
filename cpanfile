requires "Mojolicious", "";
requires "DateTime::Format::DateParse", "";
requires "Number::Format", "";
requires "DBIx::Class", "";
requires "DBIx::Class::TimeStamp", "";
requires "Mojolicious::Plugin::JSONP", "";
requires "DateTime::Format::Pg", "";
# Need to load the schema w/ dbicdump
requires "DBIx::Class::Schema::Loader", "";
# Loader requires Config::General
requires "Config::General", "";
# For https get requests
requires "IO::Socket::SSL", "";
