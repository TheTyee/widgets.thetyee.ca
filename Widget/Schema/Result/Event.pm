use utf8;
package Widget::Schema::Result::Event;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Widget::Schema::Result::Event

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

=head1 TABLE: C<shares.event>

=cut

__PACKAGE__->table("shares.event");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'shares.event_id_seq'

=head2 email_from

  data_type: 'text'
  is_nullable: 0

=head2 email_to

  data_type: 'text'
  is_nullable: 0

=head2 url

  data_type: 'text'
  is_nullable: 0

=head2 title

  data_type: 'text'
  is_nullable: 0

=head2 summary

  data_type: 'text'
  is_nullable: 0

=head2 img

  data_type: 'text'
  is_nullable: 0

=head2 message

  data_type: 'text'
  is_nullable: 0

=head2 timestamp

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 0
  original: {default_value => \"now()"}

=head2 wc_sub_pref

  data_type: 'text'
  is_nullable: 0

=head2 wc_result_send

  data_type: 'text'
  is_nullable: 1

=head2 wc_result_sub

  data_type: 'text'
  is_nullable: 1

=head2 wc_status

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "shares.event_id_seq",
  },
  "email_from",
  { data_type => "text", is_nullable => 0 },
  "email_to",
  { data_type => "text", is_nullable => 0 },
  "url",
  { data_type => "text", is_nullable => 0 },
  "title",
  { data_type => "text", is_nullable => 0 },
  "summary",
  { data_type => "text", is_nullable => 0 },
  "img",
  { data_type => "text", is_nullable => 0 },
  "message",
  { data_type => "text", is_nullable => 0 },
  "timestamp",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 0,
    original      => { default_value => \"now()" },
  },
  "wc_sub_pref",
  { data_type => "text", is_nullable => 0 },
  "wc_result_send",
  { data_type => "text", is_nullable => 1 },
  "wc_result_sub",
  { data_type => "text", is_nullable => 1 },
  "wc_status",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<event_email_from_email_to_url_message_key>

=over 4

=item * L</email_from>

=item * L</email_to>

=item * L</url>

=item * L</message>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "event_email_from_email_to_url_message_key",
  ["email_from", "email_to", "url", "message"],
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2015-03-12 16:10:59
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ZcI3x7bw3Qeb7qT55vAPqQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
