#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::UserAgent;
use utf8;
use Encode;
use Data::Dumper;


use Try::Tiny;
use DateTime;
use DateTime::Format::DateParse;
use Number::Format;
use Widget::Schema;
use DBIx::Class::ResultClass::HashRefInflator;

my $config = plugin 'JSONConfig';
plugin JSONP => callback => 'cb';

my $ua = Mojo::UserAgent->new;

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

helper shares_email => sub {
    my $self = shift;
    my $url  = shift;
    my $results;
    my $rs
        = $self->search_records( 'Event', { url => { 'like', "%$url%" } } );
    my $count = $rs->count;
    $results = { url => $url, shares => $count };
    return $results;
};

helper shares_twitter => sub {
    # TODO 
    # + Replace this API with our own internal results scraper
    my $self = shift;
    my $url  = shift;
    my $API  = 'http://public.newsharecounts.com/count.json?url=';
    my $results;
    my $tx = $ua->get($API . $url);
    if (my $res = $tx->success) { 
        $results = $res->json;
    } else {
      my $err = $tx->error;
      $results->{'error_code'} = $err->{'code'};
      $results->{'error_message'} = $err->{'message'};
    }
    return $results;
};

helper get_facebook_token => sub {
    #TODO 
    # + Cache this response
    # + Return cache if fresh
    # + If not, queue a job to re-validate
    my $APP_ID = $config->{'fb_app_id'};
    my $SECRET = $config->{'fb_app_secret'};
    my $API  = 'https://graph.facebook.com/v2.1';
    my $OAUTH = "/oauth/access_token?client_id=$APP_ID&client_secret=$SECRET&grant_type=client_credentials";
    my $results;
    my $tx = $ua->get($API . $OAUTH);
    if (my $res = $tx->success) { 
        $results = $res->body;
    } else {
      my $err = $tx->error;
      $results->{'error_code'} = $err->{'code'};
      $results->{'error_message'} = $err->{'message'};
    }
    return $results;
};

helper shares_facebook => sub {
    # TODO
    # + Cache this response too
    my $self = shift;
    my $url  = shift;
    my $API  = 'https://graph.facebook.com/v2.1';
    my $token = $self->get_facebook_token;
    my $results;
    my $tx = $ua->get($API . '/?id=' . $url . '&' . $token);
    if (my $res = $tx->success) { 
        $results = $res->json;
    } else {
      my $err = $tx->error;
      $results->{'error_code'} = $err->{'code'};
      $results->{'error_message'} = $err->{'message'};
      $results->{'token'} = $token;
    }
    return $results;
};

get '/' => sub {
    my $self = shift;
    $self->render( 'index' );
};

# Provide a data structure for displaying an updated builder list

get '/builderlist' => sub {
    my $self = shift;

    # Dates
    my $date_start = $self->param( 'date_start' ) || '2012-01-01';
    my $dt_start = DateTime::Format::DateParse->parse_datetime( $date_start );
    my $dtf      = $self->schema->storage->datetime_parser;

    # Transactions and calculations
    my $rs = $self->search_records(
        'Transaction',
        {
            # TODO re-implement with clean data
            trans_date => { '>' => $dtf->format_datetime( $dt_start ) }
        }
    );

    my $count        = $rs->count;
    my $monthlycount = 0;

# Need to multiply those rows with a value in plan_code by $multiplier months (default 12)
    my @contributors;
    while ( my $trans = $rs->next ) {

        if ( $self->param( 'monthlyonly' ) ) {
            next
                if ( $trans->plan_code eq ''
                || $trans->plan_code =~ /^ *$/
                || $trans->plan_code eq "cancelled" );
        }

        # only non-anon contribs
        next
            unless ( $trans->pref_anonymous
            && $trans->pref_anonymous eq 'Yes' );
        my $n = $trans->first_name . $trans->last_name;

        # next if $n =~ /\d+/;    # No card numbers for names please
        my $contrib = {
            first_name => $trans->first_name,
            last_name  => $trans->last_name,
        };
        push @contributors, $contrib;
    }

    @contributors
        = sort { $a->{'last_name'} cmp $b->{'last_name'} } @contributors;
    my $result = {
        builderlist => \@contributors,
        count       => $count,
    };
    $self->stash( result => $result, );
    $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
    $self->respond_to(
        json => sub        { $self->render_jsonp( { result => $result } ); },
        html => { template => 'builderlist' },
        any  => { text     => '',                 status   => 204 }
    );
};


#-------------------------------------------------------------------------------
#  Endpoints for returning share-related information
#-------------------------------------------------------------------------------
group {
    under '/shares/';
        get '/email' => sub { # /shares/email/?limit=X&days=Y
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

            my @encoded;
            my $tx;
            # Ridiculous Bryan hack to decode the utf-8 characters from the db
            foreach my $url (@urls) {                 
                  my %newhash;
                 foreach my $key (keys %$url) {
                   $newhash{$key} = decode("utf-8", ($url->{$key}) );
                  # $newhash{$key}  = $url->{$key};
                 }
                    push (@encoded, \%newhash );
                }
            my $result = { result => \@encoded, };            
            $self->stash( result => $result, );
            $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
            $self->respond_to(
                json => sub     { $self->render_jsonp( { result => $result } ); },
                html => { template => 'dump' },
                any  => { text     => '',                 status   => 204 }
            );
        };
    under '/shares/url' => sub {
            my $self = shift;
            my $url  = $self->param( 'url' );
            # Make sure that all URL requests are legit
            return 1 if $url =~ m!^http://thetyee\.ca|^http://preview\.thetyee\.ca!;
            $self->stash( result => 'not permitted', );
            $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
            $self->respond_to(
                json => { json => { message => 'not permitted' }, status => 401 },
                html => { template => 'dump' },
                any  => { text     => '',                 status   => 204 }
            );
            return undef;
        };
        get '/all/' => sub { # /shares/url/all?=url=http://...
            my $self = shift;
            my $url  = $self->param( 'url' );
            my $fb = $self->shares_facebook($url);
            my $tw = $self->shares_twitter($url);
            my $em = $self->shares_email($url);
            my $fb_shares = $fb->{'share'}{'share_count'};
            my $tw_shares = $tw->{'count'};
            my $em_shares = $em->{'shares'};
            my $total = $fb_shares + $tw_shares + $em_shares;
            my $result = {
                facebook => $fb,
                twitter  => $tw,
                email    => $em,
                total    => $total
            };
            $self->stash( result => $result, );
            $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
            $self->respond_to(
                json => sub        { $self->render_jsonp( { result => $result } ); },
                html => { template => 'dump' },
                any  => { text     => '',                 status   => 204 }
            );
        };

        get '/email' => sub { # /shares/url/email?url=http://...
            my $self = shift;
            my $url  = $self->param( 'url' );
            my $result = $self->shares_email($url);
            $self->stash( result => $result, );
            $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
            $self->respond_to(
                json => sub        { $self->render_jsonp( { result => $result } ); },
                html => { template => 'dump' },
                any  => { text     => '',                 status   => 204 }
            );
        };

        get '/twitter' => sub { # /shares/url/twitter?url=http://...
            my $self = shift;
            my $url  = $self->param( 'url' );
            my $result = $self->shares_twitter($url);
            $self->stash( result => $result, );
            $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
            $self->respond_to(
                json => sub        { $self->render_jsonp( { result => $result } ); },
                html => { template => 'dump' },
                any  => { text     => '',                 status   => 204 }
            );
        };

        get '/facebook' => sub { # /shares/url/facebook?url=http://...
            my $self = shift;
            my $url  = $self->param( 'url' );
            my $result = $self->shares_facebook($url);
            $self->stash( result => $result, );
            $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
            $self->respond_to(
                json => sub        { $self->render_jsonp( { result => $result } ); },
                html => { template => 'dump' },
                any  => { text     => '',                 status   => 204 }
            );
        };

}; # End group.

# Provide a data structure for following progress on fundraising campaigns
get '/progress' => sub {
    my $self = shift;
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
    my $rs = $self->search_records(
        'Transaction',
        {
            trans_date => { '>' => $dtf->format_datetime( $dt_start ) }
        }
    );
    my $count        = $rs->count;
    my $monthlycount = 0;
    my $onetimecount = 0;

# Need to multiply those rows with a value in plan_code by $multiplier months (default 12)
    my $total        = 0;
    my $monthlytotal = 0;
    my $onetimetotal = 0;
    my @contributors;
    my @monthlycontributors;
    my @onetimecontributors;
    while ( my $trans = $rs->next ) {

        if (   $trans->plan_code
            && $trans->plan_name ne "cancelled"
            && $trans->plan_code ne '' )
        {    #update to plan_code later when recurly sync fixed
            $total        += $trans->amount_in_cents / 100 * $multiplier;
            $monthlytotal += $trans->amount_in_cents / 100 * $multiplier;
            $monthlycount++;
        }
        else {
            $total        += $trans->amount_in_cents / 100;
            $onetimetotal += $trans->amount_in_cents / 100;
            $onetimecount++;
        }

        only non-anon contribs next
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

        if (   $trans->plan_code
            && $trans->plan_name ne "cancelled"
            && $trans->plan_code ne '' )
        {                       #see above not about plan_code
            push @monthlycontributors, $contrib;
        }
        else {
            push @onetimecontributors, $contrib;
        }

    }
    @contributors = reverse @contributors;
    my $percentage = $formatter->round( $total / $goal * 100, 0 );
    my $monthlypercentage
        = $formatter->round( $monthlytotal / $goal * 100, 0 );
    my $remaining        = $goal - $total;
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
        raised_monthly   => $monthlytotal,
        raised_monthly_formatted =>
            $formatter->format_price( $monthlytotal, 0, '$' ),
        raised_onetime => $onetimetotal,
        raised_onetime_formatted =>
            $formatter->format_price( $onetimetotal, 0, '$' ),
        people             => $count,
        people_monthly     => $monthlycount,
        people_onetime     => $onetimecount,
        percentage         => $percentage,
        percentage_monthly => $monthlypercentage,
        remaining          => $formatter->format_price( $remaining, 0, '$' ),
        remaining_monthly =>
            $formatter->format_price( $monthlyremaining, 0, '$' ),
        contributors         => \@contributors,
        contributors_monthly => \@monthlycontributors,
        contributors_onetime => \@onetimecontributors,
        votes                => \@votes,
        version              => $config->{'app_version'},
    };
    $self->stash( progress => $progress, );
    $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
    $self->respond_to(
        json => sub { $self->render_jsonp( { result => $progress } ); },
        html => { template => 'progress' },
        any  => { text     => '', status => 204 }
    );
};

app->secrets( [ $config->{'app_secret'} ] );
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
%= dumper ( $result);
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
