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
#    $url =~ s/https/http/g;

    my $API  = 'https://counts.twitcount.com/counts.php?url=';
    
    my $results;
    my $tx = $ua->get( $API . $url );
     #   app->log->debug ($API . $url);
    if ( my $res = $tx->success ) {
        $results = $res->json;
    }
    else {
        my $err = $tx->error;
        $results->{'error_code'}    = $err->{'code'};
        $results->{'error_message'} = $err->{'message'};
    }

   #  app->log->debug ("twitter shares return : \n" . Dumper ($results) .  "\n");

    return $results;
};

helper get_facebook_token => sub {

    #TODO
    # + Cache this response
    # + Return cache if fresh
    # + If not, queue a job to re-validate
    my $APP_ID = $config->{'fb_app_id'};
    my $SECRET = $config->{'fb_app_secret'};
    my $API    = 'https://graph.facebook.com/v3.2';
    my $OAUTH
        = "/oauth/access_token?client_id=$APP_ID&client_secret=$SECRET&grant_type=client_credentials";
    my $results;
    my $tx = $ua->get( $API . $OAUTH );
   if ( my $res = $tx->success ) {
        # app->log->debug ("token was successful");
        $results = $res->json;
        # app->log->debug("json: " . $results);
    }
    else {
        my $err = $tx->error;
        $results->{'error_code'}    = $err->{'code'};
        $results->{'error_message'} = $err->{'message'};
    }


    return $results->{"access_token"};
};

helper shares_facebook_sharedcount => sub {
  my $self  = shift;
    my $url   = shift;
    my $API   = 'https://api-v2.sharedcount.com/v2.0/shares';
 my $results;
    my $tx = $ua->get( $API . '/?url=' . $url . '&apikey=' . $config->{'sharedcount_api'});
    if ( my $res = $tx->success ) {
        $results = $res->json;
   #     app->log->debug ("fb shares return : \n" . Dumper ($results) .  "\n");
   #      app->log->debug ($API . '/?url=' . $url  . "\n");

    }
    else {
        my $err = $tx->error;
        $results->{'error_code'}    = $err->{'code'};
        $results->{'error_message'} = $err->{'message'};
        $results->{'url'}         = $url;
        $results->{'dump'}      = Dumper ($results);
    }
    return $results;

};


helper shares_facebook => sub {

    # TODO
    # + Cache this response too
    my $self  = shift;
    my $url   = shift;
    my $API   = 'https://graph.facebook.com/v3.2';
    my $token = $self->get_facebook_token;
    # app->log->error("got token: " . $token);
    my $results;
    my $tx = $ua->get( $API . '/?id=' . $url . '&access_token=' . $token . "&fields=engagement" );
    if ( my $res = $tx->success ) {
        $results = $res->json;
       #  app->log->debug ("fb shares return : \n" . Dumper ($results) .  "\n");
       #  app->log->debug ($API . '/?id=' . $url . '&access_token=' . $token .  "\n");

    }
    else {
        my $err = $tx->error;
        $results->{'error_code'}    = $err->{'code'};
        $results->{'error_message'} = $err->{'message'};
        $results->{'token'}         = $token;
        $results->{'url'}         = $url;
        $results->{'dump'}      = Dumper ($results);
    }
    return $results;
};

get '/' => sub {
    my $self = shift;
    $self->render( 'index' );
};


helper submit_facebook => sub {
    my $self  = shift;
    my $url   = shift;
    my $scrape = shift;
    my $denylist = shift;
    my $fields = shift;
        my $API   = "https://graph.facebook.com/?id=" .$url . "&scopes=&access_token=" . $config->{'fb_apitoken'}; 
    my $results;
    
  my $json =  {id => $url, scopes =>  $config->{'fb_apiscope'}, access_token => $config->{'fb_apitoken'} };
  
  if ($scrape) {$json -> {'scrape'} = 'true'};
  if ($denylist) { $json -> {'denylist'} = 'true'};
  if ($fields) { $json -> {'fields'} = 'scopes'; delete  $json -> {'scopes'};}
               
   app->log->debug ("json being sent:" . Dumper ($json) .  "\n");

   
    my $tx = $ua->post('https://graph.facebook.com/' => json => $json );
    
    if ( my $res = $tx->success ) {
        $results = $res->json;
        app->log->debug ("fb submit return : \n" . Dumper ($res) .  "\n");
        app->log->debug ($API . '/?id=' . $url . '&access_token=' . $config->{'fb_apitoken'} . " Scrape = $scrape denylist = $denylist \n");
        app->log->debug ( "res->body = ".  $res->body . "\n");
    }
    else {
        my $err = $tx->error;
        $results->{'error_code'}    = $err->{'code'};
        $results->{'error_message'} = $err->{'message'};
        $results->{'token'}         = $config->{'fb_apitoken'};
        $results->{'url'}         = $url;
        $results->{'dump'}      = Dumper ($results);
    }
    return $results;
};
#-------------------------------------------------------------------------------
#  Endpoints for returning share-related information
#-------------------------------------------------------------------------------
group {
    under '/shares/';
    get '/email' => sub {    # /shares/email/?limit=X&days=Y
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
            {   select => [ 'url', { count => 'url' }, 'title' ],
                as           => [qw/ url count title /],
                group_by     => [qw/ url title /],
                order_by     => [ { -desc => 'count' }, { -asc => 'title' } ],
                rows         => $limit,
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );

        my @encoded;
        my $tx;

        # Ridiculous Bryan hack to decode the utf-8 characters from the db
        foreach my $url ( @urls ) {
            my %newhash;
            foreach my $key ( keys %$url ) {
                $newhash{$key} = decode( "utf-8", ( $url->{$key} ) );

                # $newhash{$key}  = $url->{$key};
            }
            push( @encoded, \%newhash );
        }
        my $result = { urls => \@encoded, };
        $self->stash( result => $result, );
        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => sub { $self->render_jsonp( { result => $result } ); },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
    };
    under '/shares/url' => sub {
        my $self = shift;
        my $url  = $self->param( 'url' );

        # Make sure that all URL requests are legit
        return 1
            if $url =~ m!^http://thetyee\.ca|^http://preview\.thetyee\.ca|^https://thetyee\.ca|^https://preview\.thetyee\.ca!;
        $self->stash( result => 'not permitted', );
        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => { json => { message => 'not permitted' }, status => 401 },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
        return undef;
    };
    get '/all/' => sub {    # /shares/url/all?=url=http://...
        my $self      = shift;
        my $url       = $self->param( 'url' );
          #      app->log->debug ("all shares url : $url \n");
        my $fb        = $self->shares_facebook_sharedcount( $url );
        my $tw        = $self->shares_twitter( $url );
        my $em        = $self->shares_email( $url );
#        my $fb_shares = $fb->{'engagement'}{'comment_count'} + $fb->{'engagement'}{'reaction_count'} + $fb->{'engagement'}{'share_count'} ;
        my $fb_shares = $fb->{'Facebook'}{'total_count'};
        my $tw_shares = $tw->{'count'};
        my $em_shares = $em->{'shares'};
        my $total     = $fb_shares + $tw_shares + $em_shares;
        my $result    = {
            facebook => $fb,
            twitter  => $tw,
            email    => $em,
            total    => $total
        };
        $self->stash( result => $result, );
        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => sub { $self->render_jsonp( { result => $result } ); },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
    };

    get '/email' => sub {    # /shares/url/email?url=http://...
        my $self   = shift;
        my $url    = $self->param( 'url' );
        my $result = $self->shares_email( $url );
        $self->stash( result => $result, );
        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => sub { $self->render_jsonp( { result => $result } ); },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
    };

    get '/twitter' => sub {    # /shares/url/twitter?url=http://...
        my $self   = shift;
        my $url    = $self->param( 'url' );
        my $result = $self->shares_twitter( $url );
        $self->stash( result => $result, );
        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => sub { $self->render_jsonp( { result => $result } ); },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
    };

    get '/facebook' => sub {    # /shares/url/facebook?url=http://...
        my $self   = shift;
        my $url    = $self->param( 'url' );
        my $result = $self->shares_facebook_sharedcount( $url );
        $self->stash( result => $result, );
        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => sub { $self->render_jsonp( { result => $result } ); },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
    };

};    # End group.


   get '/submit_fb' => sub {    # 
        my $self   = shift;
        my $url    = $self->param( 'url' );
        my $scrape = $self->param( 'scrape');
        my $denylist = $self->param( 'denylist');
        my $fields = $self->param( 'fields');

        my $result = $self->submit_facebook($url, $scrape, $denylist, $fields);
                $self->stash( result => $result, );
                        $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $self->respond_to(
            json => sub { $self->render_jsonp( { result => $result } ); },
            html => { template => 'dump' },
            any  => { text     => '', status => 204 }
        );
        
    };


# Provide a data structure for displaying an updated builder list
get '/builderlist' => sub {
    my $self = shift;
    my $campaign   = $self->param( 'campaign' );        

    # Dates
    my $date_start = $self->param( 'date_start' ) || '2012-01-01';
    my $dt_start = DateTime::Format::DateParse->parse_datetime( $date_start );
    my $dtf      = $self->schema->storage->datetime_parser;

    # Transactions and calculations
    my $rs = $self->search_records(
        'Transaction',
        {
            # TODO re-implement with clean data
                     trans_date => { '>' => $dtf->format_datetime( $dt_start )},
	#		 appeal_code => {'=' => $campaign },

  			   
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

        # Only non-anon contribs
        #next
        #unless ( $trans->pref_anonymous
        #&& $trans->pref_anonymous eq 'Yes' );
        my $first;
        my $last;
        if ( $trans->on_behalf_of ) { # People who gave on behalf of another
            if ( $trans->pref_anonymous && $trans->pref_anonymous eq 'No' ) { # If anon
                $first
                    = 'In '
                    . $trans->on_behalf_of . ' of '
                    . $trans->on_behalf_of_name_first;
                $last = $trans->on_behalf_of_name_last;
            }
            else { # If not anon
                $first = $trans->first_name;
                $last
                    = $trans->last_name . ' (In '
                    . $trans->on_behalf_of . ' of '
                    . $trans->on_behalf_of_name_first . ' '
                    . $trans->on_behalf_of_name_last . ')';
            }
        }
        else {
            $first = $trans->first_name;
            $last  = $trans->last_name;
        }
        if ( $trans->pref_anonymous && $trans->pref_anonymous eq 'No' && !$trans->on_behalf_of ) { # If anon
            $first = '';
            $last  = '';
        }
        my $n = $first . ' ' . $last;
        next if $n =~ /\d+/;    # No card numbers for names please
        say Dumper( $n );
        next if $n =~ /^\s+$/;     # No anonymous

        # Otherwise, add to the contributors list
        my $contrib = {
            first_name => $first,
            last_name  => $last,
        };
        push @contributors, $contrib;
    }

    @contributors
        = sort { lc($a->{'last_name'}) cmp lc($b->{'last_name'}) } @contributors;
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

# Provide a data structure for following progress on fundraising campaigns
get '/progress' => sub {
    my $self       = shift;
    my $campaign   = $self->param( 'campaign' );        
    my $date_start = $self->param( 'date_start' );
    my $date_end   = $self->param( 'date_end' );
    my $goal       = $self->param( 'goal' );
    my $multiplier = $self->param( 'multiplier' ) || 12;
    my $monthly_number_only = $self->param( 'monthly_number_only' );

    # Need some better error checking for required params
    unless ( $date_start && $date_end && $goal ) {
        $self->render(
            text => 'date_start, date_end, and goal need to be supplied' );
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
#        // overwriting day calculation above to remove months//
       

 $days = ($dt_end->delta_days($today)->in_units('days'));
unless ($days == 0) { $days += -1 } ;
if ($dt_end < $today) { $days = 0};
    my $dtf = $self->schema->storage->datetime_parser;
     

    # Transactions and calculations
    my $rs = $self->search_records( 'Transaction',
        { 

	trans_date => { '>' => $dtf->format_datetime( $dt_start )} #,
       #  appeal_code => {'=' => $campaign } 
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

        # Only non-anon contribs
        next
            unless ( $trans->pref_anonymous
            && $trans->pref_anonymous eq 'Yes' );
        my $first;
        my $last;
        if ( $trans->on_behalf_of ) {
            $first
                = 'In '
                . $trans->on_behalf_of . ' of '
                . $trans->on_behalf_of_name_first;
            $last = $trans->on_behalf_of_name_last;
        }
        else {
            $first = $trans->first_name;
            $last  = $trans->last_name;
        }
        my $n = $trans->first_name . $trans->last_name;
        next if $n =~ /\d+/;    # No card numbers for names please

        my $contrib;
        if ( $trans->on_behalf_of ) {
            $contrib = {
                name  => $first . ' ' . $last,
                city  => '',
                state => '',
            };
        }
        else {
            $contrib = {
                name  => $first . ' ' . $last,
                city  => $trans->city,
                state => $trans->state,
            };
        }
        push @contributors, $contrib;

        if (   $trans->plan_code
            && $trans->plan_name ne "cancelled"
            && $trans->plan_code ne '' )
        {    #see above not about plan_code
            push @monthlycontributors, $contrib;
        }
        else {
            push @onetimecontributors, $contrib;
        }

    }
    @contributors = reverse @contributors;
    
     if ($monthly_number_only) {
        $total = $monthlycount;
        $monthlytotal = $monthlycount;
                               };
    
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
    #    duration        => Dumper($duration),
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
        today               => $today
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

