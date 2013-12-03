package RplusMgmt::Controller::API::Client;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;

sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'read');

    # Not Implemented

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'read');

    # Retrieve client (by id or phone_num)
    my $client;
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } elsif (my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'))) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef])->[0];
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    my $res = {
        id => $client->id,
        name => $client->name,
        phone_num => $client->phone_num,
        add_date => $self->format_datetime($client->add_date),
        description => $client->description,
    };

    if ($self->param_b('with_subscriptions')) {
        $res->{subscriptions} = [];

        # Retrieve client subscriptions including count of found realty
        my $sth = $self->db->dbh->prepare(qq{
            SELECT S.*, count(SR.id) realty_count
            FROM subscriptions S
            LEFT JOIN subscription_realty SR ON (SR.subscription_id = S.id)
            WHERE S.client_id = ? AND S.end_date IS NOT NULL AND S.delete_date IS NULL AND SR.delete_date IS NULL
            GROUP BY S.id
            ORDER BY S.id
        });
        $sth->execute($client->id);
        while (my $row = $sth->fetchrow_hashref) {
            my $x = {
                id => $row->{id},
                client_id => $row->{client_id},
                user_id => $row->{user_id},
                offer_type_code => $row->{offer_type_code},
                queries => $row->{queries},
                add_date => $self->format_datetime($row->{add_date}),
                end_date => $self->format_datetime($row->{end_date}),
                realty_count => $row->{realty_count},
                realty_limit => $row->{realty_limit},
                send_owner_phone => $row->{send_owner_phone} ? \1 : \0,
            };
            push @{$res->{subscriptions}}, $x;
        }
    }

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write');

    # Retrieve client
    my $client;
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $client = Rplus::Model::Client->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    # Validation
    $self->validation->required('phone_num')->is_phone_num;

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {phone_num => 'Invalid value'} if $self->validation->has_error('phone_num');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Prepare data
    my $name = $self->param_n('name');
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));
    my $description = $self->param_n('description');

    # Save
    $client->name($name);
    $client->phone_num($phone_num);
    $client->description($description);

    eval {
        $client->save($client->id ? (changes_only => 1) : (insert => 1));
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    return $self->render(json => {status => 'success', id => $client->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write');

    my $id = $self->param('id');

    # Delete client
    my $num_rows_updated = Rplus::Model::Client::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    # Delete client subscriptions
    $num_rows_updated = Rplus::Model::Subscription::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [client_id => $id, delete_date => undef],
    );

    # I think, it's unnecessary to delete subscription realty & client owned realty

    return $self->render(json => {status => 'success'});
}

sub subscribe {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'subscribe');

    # Validation
    $self->validation->required('phone_num')->is_phone_num;
    $self->validation->required('q');
    $self->validation->required('offer_type_code')->in(qw(sale rent));
    $self->validation->optional('end_date')->is_datetime;

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {phone_num => 'Invalid value'} if $self->validation->has_error('phone_num');
        push @errors, {q => 'Invalid value'} if $self->validation->has_error('q');
        push @errors, {offer_type_code => 'Invalid value'} if $self->validation->has_error('offer_type_code');
        push @errors, {end_date => 'Invalid value'} if $self->validation->has_error('end_date');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Input params
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));
    my $q = $self->param_n('q');
    my $offer_type_code = $self->param('offer_type_code');
    my $realty_ids = Mojo::Collection->new($self->param('realty_ids[]'))->compact->uniq;
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));

    # Begin transaction
    my $db = $self->db;
    $db->begin_work;

    # Find/create client by phone number
    my $client = Rplus::Model::Client::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef], db => $db)->[0];
    if (!$client) {
        $client = Rplus::Model::Client->new(phone_num => $phone_num, db => $db);
        $client->save;
    }

    # Add subscription
    my $subscription = Rplus::Model::Subscription->new(
        client_id => $client->id,
        user_id => $self->session->{user}->{id},
        queries => [$q],
        offer_type_code => $offer_type_code,
        end_date => $end_date,
        db => $db,
    );
    $subscription->save;

    # Add realty to subscription & generate SMS
    for my $realty_id (@$realty_ids) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            query => [id => $realty_id, state_code => ['raw', 'work'], offer_type_code => $offer_type_code],
            with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
            db => $db,
        )->[0];
        if ($realty) {
            Rplus::Model::SubscriptionRealty->new(subscription_id => $subscription->id, realty_id => $realty->id, db => $db)->save;

            # Prepare SMS for client
            if ($phone_num =~ /^9\d{9}$/) {
                # TODO: Add template settings
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->address_object->name !~ /[()]/ && $realty->sublandmark ? ' ('.$realty->sublandmark->name.')' : '') if $realty->address_object;
                    push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, $realty->agent->public_name || $realty->agent->name if $realty->agent;
                    push @parts, $realty->agent->public_phone_num || $realty->agent->phone_num if $realty->agent;
                }
                my $sms_body = join(', ', @parts);
                my $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').($self->config->{subscriptions}->{contact_info} ? ' '.$self->config->{subscriptions}->{contact_info} : '');
                Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $sms_text, db => $db)->save;
            }

            # Prepare SMS for agent
            if ($realty->agent && ($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                # TODO: Add template settings
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, 'Клиент: '.$self->format_phone_num($phone_num);
                }
                my $sms_text = join(', ', @parts);
                Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text, db => $db)->save;
            }
        }
    }

    $db->commit;

    return $self->render(json => {status => 'success'});
}

1;
