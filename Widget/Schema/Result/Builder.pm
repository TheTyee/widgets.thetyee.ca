use utf8;
package Widget::Schema::Result::Builder;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Widget::Schema::Result::Builder

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=item * L<DBIx::Class::TimeStamp>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp");

=head1 TABLE: C<builderlist.builders>

=cut

__PACKAGE__->table("builderlist.builders");

=head1 ACCESSORS

=head2 subscriber_id

  data_type: 'integer'
  is_nullable: 0

=head2 first_name

  data_type: 'text'
  is_nullable: 0

=head2 last_name

  data_type: 'text'
  is_nullable: 0

=head2 builder_is_anonymous

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "subscriber_id",
  { data_type => "integer", is_nullable => 0 },
  "first_name",
  { data_type => "text", is_nullable => 0 },
  "last_name",
  { data_type => "text", is_nullable => 0 },
  "builder_is_anonymous",
  { data_type => "integer", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</subscriber_id>

=back

=cut

__PACKAGE__->set_primary_key("subscriber_id");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-11-13 14:21:00
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:P331S5FOFHs2uUTLpGo6ZA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
