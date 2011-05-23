package FixMyStreet::App::Controller::Alert;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use mySociety::EmailUtil qw(is_valid_email);

=head1 NAME

FixMyStreet::App::Controller::Alert - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 alert

Show the alerts page

=cut

sub index : Path('') : Args(0) {
    my ( $self, $c ) = @_;

    $c->stash->{cobrand_form_elements} = $c->cobrand->form_elements('alerts');

    unless ( $c->req->referer && $c->req->referer =~ /fixmystreet\.com/ ) {
        $c->forward( 'add_recent_photos', [10] );
    }
}

sub list : Path('list') : Args(0) {
    my ( $self, $c ) = @_;

    return
      unless $c->forward('setup_request')
          && $c->forward('prettify_pc')
          && $c->forward('determine_location')
          && $c->forward( 'add_recent_photos', [5] )
          && $c->forward('setup_council_rss_feeds')
          && $c->forward('setup_coordinate_rss_feeds');
}

=head2 subscribe

Target for subscribe form

=cut

sub subscribe : Path('subscribe') : Args(0) {
    my ( $self, $c ) = @_;

    if ( $c->req->param('rss') ) {
        $c->detach('rss');
    }
    elsif ( $c->req->param('rznvy') ) {
        $c->detach('subscribe_email');
    }
}

=head2 rss

Redirects to relevant RSS feed

=cut

sub rss : Private {
    my ( $self, $c ) = @_;
    my $feed = $c->req->params->{feed};

    unless ($feed) {
        $c->stash->{errors} = [ _('Please select the feed you want') ];
        $c->go('list');
    }

    my $extra_params = $c->cobrand->extra_params( $c->fake_q );
    my $url;
    if ( $feed =~ /^area:(?:\d+:)+(.*)$/ ) {
        ( my $id = $1 ) =~ tr{:_}{/+};
        $url = $c->cobrand->base_url() . '/rss/area/' . $id;
        $c->res->redirect($url);
    }
    elsif ( $feed =~ /^(?:council|ward):(?:\d+:)+(.*)$/ ) {
        ( my $id = $1 ) =~ tr{:_}{/+};
        $url = $c->cobrand->base_url() . '/rss/reports/' . $id;
        $c->res->redirect($url);
    }
    elsif ( $feed =~ /^local:([\d\.-]+):([\d\.-]+)$/ ) {
        ( my $id = $1 ) =~ tr{:_}{/+};
        $url = $c->cobrand->base_url() . '/rss/l/' . $id;
        $c->res->redirect($url);
    }
    else {
        $c->stash->{errors} = [ _('Illegal feed selection') ];
        $c->go('list');
    }
}

=head2 subscribe_email

Sign up to email alerts

=cut

sub subscribe_email : Private {
    my ( $self, $c ) = @_;

    my $type = $c->req->param('type');
    $c->stash->{email_type} = 'alert';

    my @errors;
    push @errors, _('Please enter a valid email address')
      unless is_valid_email( $c->req->param('rznvy') );
    push @errors, _('Please select the type of alert you want')
      if $type && $type eq 'local' && !$c->req->param('feed');
    if (@errors) {
        $c->stash->{errors} = \@errors;
        $c->go('updates') if $type && $type eq 'updates';
        $c->go('list') if $type && $type eq 'local';
        $c->go('index');
    }

    my $email = $c->req->param('rznvy');
    $c->stash->{email} = $email;
    $c->forward('process_user');

    if ( $type eq 'updates' ) {
        $c->forward('set_update_alert_options');
    }
    elsif ( $type eq 'problems' ) {

#        $alert_id = FixMyStreet::Alert::create($email, 'new_problems', $cobrand, $cobrand_data);
    }
    elsif ( $type eq 'local' ) {
        $c->forward('set_local_alert_options');
    }
    else {
        throw FixMyStreet::Alert::Error('Invalid type');
    }

    $c->forward('create_alert');
    $c->forward('send_confirmation_email');
}

sub updates : Path('updates') : Args(0) {
    my ( $self, $c ) = @_;

    $c->stash->{email} = $c->req->param('rznvy');
    $c->stash->{problem_id} = $c->req->param('id');
    $c->stash->{cobrand_form_elements} = $c->cobrand->form_elements('alerts');
}

=head2 confirm

Confirm signup to an alert. Forwarded here from Tokens.

=cut

sub confirm : Private {
    my ( $self, $c ) = @_;

    my $alert = $c->stash->{alert};
    $c->stash->{template} = 'alert/confirm.html';

    if ( $c->stash->{confirm_type} eq 'subscribe' ) {
        $alert->confirm();
        $alert->update;
    }
    elsif ( $c->stash->{confirm_type} eq 'unsubscribe' ) {
        $alert->delete();
        $alert->update;
    }
}

=head2 create_alert

Take the alert options from the stash and use these to create a new
alert. If it finds an existing alert that's the same then use that

=cut 

sub create_alert : Private {
    my ( $self, $c ) = @_;

    my $options = $c->stash->{alert_options};

    my $alert = $c->model('DB::Alert')->find($options);

    unless ($alert) {
        $options->{cobrand}      = $c->cobrand->moniker();
        $options->{cobrand_data} = $c->cobrand->extra_update_data();

        $alert = $c->model('DB::Alert')->new($options);
        $alert->insert();
    }

    $c->stash->{alert} = $alert;

    $c->log->debug( 'created alert ' . $alert->id );
}

=head2 set_update_alert_options

Set up the options in the stash required to create a problem update alert

=cut

sub set_update_alert_options : Private {
    my ( $self, $c ) = @_;

    my $report_id = $c->req->param('id');

    my $options = {
        user       => $c->stash->{alert_user},
        alert_type => 'new_updates',
        parameter  => $report_id,
    };

    $c->stash->{alert_options} = $options;
    $c->forward('create_alert');
}

=head2 set_local_alert_options

Set up the options in the stash required to create a local problems alert

=cut

sub set_local_alert_options : Private {
    my ( $self, $c ) = @_;

    my $feed = $c->req->param('feed');

    my ( $type, @params, $alert );
    if ( $feed =~ /^area:(?:\d+:)?(\d+)/ ) {
        $type = 'area_problems';
        push @params, $1;
    }
    elsif ( $feed =~ /^council:(\d+)/ ) {
        $type = 'council_problems';
        push @params, $1, $1;
    }
    elsif ( $feed =~ /^ward:(\d+):(\d+)/ ) {
        $type = 'ward_problems';
        push @params, $1, $2;
    }
    elsif ( $feed =~
        m{ \A local: ( [\+\-]? \d+ \.? \d* ) : ( [\+\-]? \d+ \.? \d* ) }xms )
    {
        $type = 'local_problems';
        push @params, $1, $2;
    }


    my $options = {
        user       => $c->stash->{alert_user},
        alert_type => $type
    };

    if ( scalar @params == 1 ) {
        $options->{parameter} = $params[0];
    }
    elsif ( scalar @params == 2 ) {
        $options->{parameter}  = $params[0];
        $options->{parameter2} = $params[1];
    }

    $c->stash->{alert_options} = $options;
}

=head2 send_confirmation_email

Generate a token and send out an alert subscription confirmation email and
then display confirmation page.

=cut

sub send_confirmation_email : Private {
    my ( $self, $c ) = @_;

    my $token = $c->model("DB::Token")->create(
        {
            scope => 'alert',
            data  => {
                id    => $c->stash->{alert}->id,
                type  => 'subscribe',
                email => $c->stash->{alert}->user->email
            }
        }
    );

    $c->stash->{token_url} = $c->uri_for_email( '/A', $token->token );

    my $sender = mySociety::Config::get('CONTACT_EMAIL');

    $c->send_email(
        'alert-confirm.txt',
        {
            to   => $c->stash->{alert}->user->email,
            from => $sender
        }
    );

    $c->stash->{template} = 'email_sent.html';
}

=head2 prettify_pc

This will canonicalise and prettify the postcode and stick a pretty_pc and pretty_pc_text in the stash.

=cut

sub prettify_pc : Private {
    my ( $self, $c ) = @_;

    my $pretty_pc = $c->req->params->{'pc'};

    if ( mySociety::PostcodeUtil::is_valid_postcode( $c->req->params->{'pc'} ) )
    {
        $pretty_pc = mySociety::PostcodeUtil::canonicalise_postcode(
            $c->req->params->{'pc'} );
        my $pretty_pc_text = $pretty_pc;
        $pretty_pc_text =~ s/ //g;
        $c->stash->{pretty_pc_text} = $pretty_pc_text;

        # this may be better done in template
        $pretty_pc =~ s/ /&nbsp;/;
    }

    $c->stash->{pretty_pc} = $pretty_pc;

    return 1;
}

sub council_options : Private {
    my ( $self, $c ) = @_;

    if ( $c->config->{COUNTRY} eq 'NO' ) {

#    my ($options, $options_start, $options_end);
#    if (mySociety::Config::get('COUNTRY') eq 'NO') {
#
#        my (@options, $fylke, $kommune);
#        foreach (values %$areas) {
#            if ($_->{type} eq 'NKO') {
#                $kommune = $_;
#            } else {
#                $fylke = $_;
#            }
#        }
#        my $kommune_name = $kommune->{name};
#        my $fylke_name = $fylke->{name};
#
#        if ($fylke->{id} == 3) { # Oslo
#
#            push @options, [ 'council', $fylke->{id}, Page::short_name($fylke),
#                sprintf(_("Problems within %s"), $fylke_name) ];
#
#            $options_start = "<div><ul id='rss_feed'>";
#            $options = alert_list_options($q, @options);
#            $options_end = "</ul>";
#
#        } else {
#
#            push @options,
#                [ 'area', $kommune->{id}, Page::short_name($kommune), $kommune_name ],
#                [ 'area', $fylke->{id}, Page::short_name($fylke), $fylke_name ];
#            $options_start = '<div id="rss_list">';
#            $options = $q->p($q->strong(_('Problems within the boundary of:'))) .
#                $q->ul(alert_list_options($q, @options));
#            @options = ();
#            push @options,
#                [ 'council', $kommune->{id}, Page::short_name($kommune), $kommune_name ],
#                [ 'council', $fylke->{id}, Page::short_name($fylke), $fylke_name ];
#            $options .= $q->p($q->strong(_('Or problems reported to:'))) .
#                $q->ul(alert_list_options($q, @options));
#            $options_end = $q->p($q->small(_('FixMyStreet sends different categories of problem
#to the appropriate council, so problems within the boundary of a particular council
#might not match the problems sent to that council. For example, a graffiti report
#will be sent to the district council, so will appear in both of the district
#council&rsquo;s alerts, but will only appear in the "Within the boundary" alert
#for the county council.'))) . '</div><div id="rss_buttons">';
#
#        }
#
    }
}

sub process_user : Private {
    my ( $self, $c ) = @_;

    my $email = $c->stash->{email};
    my $alert_user = $c->model('DB::User')->find_or_new( { email => $email } );
    $c->stash->{alert_user} = $alert_user;
}

=head2 setup_coordinate_rss_feeds

Takes the latitide and longitude from the stash and uses them to generate uris
for the local rss feeds

=cut 

sub setup_coordinate_rss_feeds : Private {
    my ( $self, $c ) = @_;

    $c->stash->{rss_feed_id} =
      sprintf( 'local:%s:%s', $c->stash->{latitude}, $c->stash->{longitude} );

    my $rss_feed;
    if ( $c->stash->{pretty_pc_text} ) {
        $rss_feed =
          $c->cobrand->uri( "/rss/pc/" . $c->stash->{pretty_pc_text},
            $c->fake_q );
    }
    else {
        $rss_feed = $c->cobrand->uri(
            sprintf( "/rss/l/%s,%s",
                $c->stash->{latitude},
                $c->stash->{longitude} ),
            $c->fake_q
        );
    }

    $c->stash->{rss_feed_uri} = $rss_feed;

    $c->stash->{rss_feed_2k} = $c->cobrand->uri( $rss_feed . '/2', $c->fake_q );
    $c->stash->{rss_feed_5k} = $c->cobrand->uri( $rss_feed . '/5', $c->fake_q );
    $c->stash->{rss_feed_10k} =
      $c->cobrand->uri( $rss_feed . '/10', $c->fake_q );
    $c->stash->{rss_feed_20k} =
      $c->cobrand->uri( $rss_feed . '/20', $c->fake_q );

    return 1;
}

=head2 setup_council_rss_feeds

Generate the details required to display the council/ward/area RSS feeds

=cut

sub setup_council_rss_feeds : Private {
    my ( $self, $c ) = @_;

    $c->stash->{council_check_action} = 'alert';
    unless ( $c->forward('/council/load_and_check_councils_and_wards') ) {
        $c->go('index');
    }

    ( $c->stash->{options}, $c->stash->{reported_to_options} ) =
      $c->cobrand->council_rss_alert_options( $c->stash->{all_councils} );

    return 1;
}

=head2 determine_location

Do all the things we need to do to work out where the alert is for
and to setup the location related things for later

=cut

sub determine_location : Private {
    my ( $self, $c ) = @_;

    # Try to create a location for whatever we have
    unless ( $c->forward('/location/determine_location_from_coords')
        || $c->forward('/location/determine_location_from_pc') )
    {

        if ( $c->stash->{possible_location_matches} ) {
            $c->stash->{choose_target_uri} = $c->uri_for('/alert/list');
            $c->detach('choose');
        }

        $c->go('index') if $c->stash->{location_error};
    }

    # truncate the lat,lon for nicer urls
    ( $c->stash->{latitude}, $c->stash->{longitude} ) =
      map { Utils::truncate_coordinate($_) }
      ( $c->stash->{latitude}, $c->stash->{longitude} );

    my $dist =
      mySociety::Gaze::get_radius_containing_population( $c->stash->{latitude},
        $c->stash->{longitude}, 200000 );
    $dist                          = int( $dist * 10 + 0.5 );
    $dist                          = $dist / 10.0;
    $c->stash->{population_radius} = $dist;

    return 1;
}

=head2 add_recent_photos

    $c->forward( 'add_recent_photos', [ $num_photos ] );

Adds the most recent $num_photos to the template. If there is coordinate 
and population radius information in the stash uses that to limit it.

=cut

sub add_recent_photos : Private {
    my ( $self, $c, $num_photos ) = @_;

    if (    $c->stash->{latitude}
        and $c->stash->{longitude}
        and $c->stash->{population_radius} )
    {

        $c->stash->{photos} = $c->cobrand->recent_photos(
            $num_photos,
            $c->stash->{latitude},
            $c->stash->{longitude},
            $c->stash->{population_radius}
        );
    }
    else {
        $c->stash->{photos} = $c->cobrand->recent_photos($num_photos);
    }

    return 1;
}

sub choose : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'alert/choose.html';
}


=head2 setup_request

Setup the variables we need for the rest of the request

=cut

sub setup_request : Private {
    my ( $self, $c ) = @_;

    $c->stash->{rznvy}         = $c->req->param('rznvy');
    $c->stash->{selected_feed} = $c->req->param('feed');

    if ( $c->user ) {
        $c->stash->{rznvy} ||= $c->user->email;
    }

    $c->stash->{cobrand_form_elements} = $c->cobrand->form_elements('alerts');

    return 1;
}

=head1 AUTHOR

Struan Donald

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
