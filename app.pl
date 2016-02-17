#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::UserAgent;
use Data::Dumper;
use Try::Tiny;
use DateTime;
use DateTime::Format::DateParse;
use Number::Format;
use Widget::Schema;
use DBIx::Class::ResultClass::HashRefInflator;


my $config = plugin 'JSONConfig';
plugin JSONP => callback => 'cb';

my $formatter = new Number::Format(
    -thousands_sep => ',',
    -decimal_point => '.',
);

helper schema => sub {
    my $schema = Widget::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
};

helper search_records => sub {
    my $self      = shift;
    my $resultset = shift;
    my $search    = shift;
    my $schema    = $self->schema;
    my $rs        = $schema->resultset( $resultset )->search( $search );
    return $rs;
};

get '/' => sub {
    my $self = shift;
    $self->render( 'index' );
};

# Provide a data structure for displaying an updated builder list


get '/builderlist' => sub {
    my $self       = shift;
    # Dates
    my $date_start = $self->param( 'date_start' ) || '2012-01-01';
    my $dt_start = DateTime::Format::DateParse->parse_datetime( $date_start );
    my $dtf      = $self->schema->storage->datetime_parser;

    # Transactions and calculations
    my $rs = $self->search_records( 'Transaction',
        { 
            # TODO re-implement with clean data
            #trans_date => { '>' => $dtf->format_datetime( $dt_start ) } 
#            id => { '>' => '3282' }
#	     plan_code => {'!=', undef },
# THIS LINE MEANS ONLY NON BLANK OR NON JUST SPACE - IS NOT NULL DOESN'T WORK
	     plan_code => {'!~', '^ *$'},
	     plan_code => {'!=', ''}, 
# this below should be moved to plan_code once recurly sync script is remapped and the records updated that way too
		plan_name => {'!=', 'cancelled'}
#		pref_anonymous => {'=', 'Yes'} # removed this because need to get everyone for the count then remove the anonymous from the name list
        });

    my $count = $rs->count;	
    my $monthlycount = 0;
    # Need to multiply those rows with a value in plan_code by $multiplier months (default 12)
    my @contributors;
    while ( my $trans = $rs->next ) {

# disabled  this monthly flag -- will always be monthly / plan until the search query is changed above
    #  if ($self->param( 'monthlyonly' ) ) {
     #     next if ($trans->plan_code eq '' || $trans->plan code =~ /^ *$/ ||  $trans->plan_code eq  "cancelled");
     #  }

        # only non-anon contribs
        next unless ( $trans->pref_anonymous && $trans->pref_anonymous eq 'Yes' );
        my $n = $trans->first_name . $trans->last_name;
        # next if $n =~ /\d+/;    # No card numbers for names please
        my $contrib = {
            first_name  => $trans->first_name,
            last_name   => $trans->last_name,
        };
        push @contributors, $contrib;
    }
   
    @contributors = sort { $a->{'last_name'} cmp $b->{'last_name'} } @contributors;
    my $result = {
        builderlist => \@contributors,
        count       => $count,
    };
    $self->stash( result => $result, );
    $self->respond_to(
        json => sub        { $self->render_jsonp( { result => $result } ); },
        html => { template => 'builderlist' },
        any  => { text     => '',                 status   => 204 }
    );
};

get '/shares/email' => sub {
    my $self  = shift;
    my $limit = $self->param( 'limit' ) || 10;
    my $days  = $self->param( 'days' ) || 7;

    # Only select records from the last X days (default: 7)
    my $today = DateTime->now( time_zone => 'America/Los_Angeles' );
    my $end   = DateTime->now( time_zone => 'America/Los_Angeles' )
    ->subtract( days => $days );
    my $dtf = $self->schema->storage->datetime_parser;
    my $rs  = $self->search_records(
        'Event',
        {   timestamp => {
                '<=', $dtf->format_datetime( $today ),
                '>=', $dtf->format_datetime( $end )
            },
        }
    );
    my $count = $rs->count;
    my @urls  = $rs->search(
        undef,
        {   select   => [ 'url', { count => 'url' }, 'title' ],
            as       => [qw/ url count title /],
            group_by => [qw/ url title /],
            order_by => [ { -desc => 'count' }, { -asc => 'title' } ],
            rows     => $limit,
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my $result = { urls => \@urls, };
    $self->stash( result => $result, );
    $self->respond_to(
        json => sub        { $self->render_jsonp( { result => $result } ); },
        html => { template => 'dump' },
        any  => { text     => '',                 status   => 204 }
    );
};

# Provide a data structure for following progress on fundraising campaigns
get '/progress' => sub {
    my $self       = shift;
    $self->res->headers->header('Access-Control-Allow-Origin' => '*');
    my $campaign   = $self->param( 'campaign' );
    my $date_start = $self->param( 'date_start' );
    my $date_end   = $self->param( 'date_end' );
    my $goal       = $self->param( 'goal' );
    my $multiplier = $self->param( 'multiplier' ) || 12;

    # Need some better error checking for required params
    unless ( $date_start && $date_end && $goal ) {
        $self->render_not_found;
        return;
    }

    # Dates
    my $dt_start = DateTime::Format::DateParse->parse_datetime( $date_start );
    my $dt_end   = DateTime::Format::DateParse->parse_datetime( $date_end );
    $dt_end->set_time_zone( 'America/Los_Angeles' );
    my $today = DateTime->now( time_zone => 'America/Los_Angeles' );
    my $duration = $dt_end->subtract_datetime( $today );
    my ( $days, $hours, $minutes )
    = $duration->in_units( 'days', 'hours', 'minutes' );
    my $dtf = $self->schema->storage->datetime_parser;

    # Transactions and calculations
    my $rs = $self->search_records( 'Transaction',
        { 
            # TODO re-implement this when data is cleaned
            #trans_date => { '>' => $dtf->format_datetime( $dt_start ) }
            id => { '>' => '3282' },
        });
    my $count = $rs->count;
    my $monthlycount = 0;
    my $onetimecount = 0;
    # Need to multiply those rows with a value in plan_code by $multiplier months (default 12)
    my $total = 0;
    my $monthlytotal = 11191;
    my $onetimetotal = 0;
    my @contributors;
    my @monthlycontributors;
    my @onetimecontributors;
    while ( my $trans = $rs->next ) {


        if ( $trans->plan_code && $trans->plan_name ne "cancelled" && $trans->plan_code ne '' ) { #update to plan_code later when recurly sync fixed
            $total += $trans->amount_in_cents / 100 * $multiplier;
            $monthlytotal += $trans->amount_in_cents / 100 * $multiplier;
            $monthlycount++;
        }
        else {
            $total += $trans->amount_in_cents / 100;
            $onetimetotal += $trans->amount_in_cents / 100;
            $onetimecount++;  
        }

        only non-anon contribs
        next
        unless ( $trans->pref_anonymous
            && $trans->pref_anonymous eq 'Yes' );
        my $n = $trans->first_name . $trans->last_name;
        next if $n =~ /\d+/;    # No card numbers for names please
        my $contrib = {
            name  => $trans->first_name . ' ' . $trans->last_name,
            city  => $trans->city,
            state => $trans->state,
        };
        push @contributors, $contrib;


        if ( $trans->plan_code && $trans->plan_name ne "cancelled"  && $trans->plan_code ne '' ) { #see above not about plan_code
            push @monthlycontributors, $contrib
        } else {
            push @onetimecontributors, $contrib;	 
        }

    }
    @contributors = reverse @contributors;
    my $percentage = $formatter->round( $total / $goal * 100, 0 );
    my $monthlypercentage = $formatter->round( $monthlytotal / $goal * 100, 0);
    my $remaining = $goal - $total;
    my $monthlyremaining = $goal - $monthlytotal;

    # News priorities
    my $priority_map = {
        1 => 'Arts & Culture',
        2 => 'Energy & Environment',
        3 => 'Trade & Foreign Policy',
        4 => 'Labour & Economy',
        5 => 'Gov\'t Accountability',
        6 => 'Inequality & Social Policy',
        7 => 'Rights & Justice',
        8 => 'Media & Digital Policy',
        0 => 'Tyee\'s Choice',
    };

    # Count distinct non-null values from pref_newspriorities
    my @priorities = $rs->search(
        { pref_newspriority => { '!=' => undef } },
        {   select =>
            [ 'pref_newspriority', { count => 'pref_newspriority' } ],
            as           => [qw/ pref_newspriority count /],
            group_by     => [qw/ pref_newspriority /],
            order_by     => { -desc => 'count' },
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    # Provide the vote count with priority names
    my @votes;
    foreach my $priority ( @priorities ) {
        my $vote = {
            count => $priority->{'count'},
            name  => $priority_map->{ $priority->{'pref_newspriority'} },
        };
        push @votes, $vote;
    }

    # Only the top-three votes
    @votes = @votes[ 0 .. 2 ] if @votes;

    # Data structure to return to requests
    my $progress = {
        campaign             => $campaign,
        date_start           => $dt_start->datetime(),
        date_start_formatted => $dt_start->month_name . ' '
        . $dt_start->day . ', '
        . $dt_start->year,
        date_end           => $dt_end->datetime(),
        date_end_formatted => $dt_end->month_name . ' '
        . $dt_end->day . ', '
        . $dt_end->year,
        left_days        => $days,
        left_mins        => $minutes,
        left_hours       => $hours,
        goal             => $goal,
        goal_formatted   => $formatter->format_price( $goal, 0, '$' ),
        raised           => $total,
        raised_formatted => $formatter->format_price( $total, 0, '$' ),
        raised_monthly 	 => $monthlytotal,
        raised_monthly_formatted => $formatter->format_price( $monthlytotal, 0, '$' ),
        raised_onetime   => $onetimetotal,
        raised_onetime_formatted => $formatter->format_price( $onetimetotal, 0, '$' ),
        people           => $count,
        people_monthly   => $monthlycount,
        people_onetime   => $onetimecount,
        percentage       => $percentage,
        percentage_monthly => $monthlypercentage,
        remaining        => $formatter->format_price( $remaining, 0, '$' ),
        remaining_monthly        => $formatter->format_price( $monthlyremaining, 0, '$' ),
        contributors     => \@contributors,
        contributors_monthly => \@monthlycontributors,
        contributors_onetime => \@onetimecontributors,
        votes            => \@votes,
        version          => $config->{'app_version'},
    };
    $self->stash( progress => $progress, );
    $self->respond_to(
        json => sub { $self->render_jsonp( { result => $progress } ); },
        html => { template => 'progress' },
        any  => { text     => '', status => 204 }
    );
};

app->secret( $config->{'app_secret'} );
app->start;

__DATA__

@@ index.html.ep
% layout 'default';
% title 'widgets.thetyee.ca';

@@ progress.html.ep
% layout 'default';
% title 'HTML output for testing';
<pre>
%= dumper ( $progress );
</pre>

@@ builderlist.html.ep
% layout 'default';
% title 'HTML output for testing';
<pre>
%= dumper ( $result );
</pre>
@@ dump.html.ep
% layout 'default';
% title 'HTML output for testing';
<pre>
%= dumper ( $result );
</pre>
@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
<head>
<link rel="shortcut icon" href="<%= $config->{'static_asset_path'} %>/ui/img/favicon.ico">
<title><%= title %></title>
</head>
<body><%= content %></body>
</html>
