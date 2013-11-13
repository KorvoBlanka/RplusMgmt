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

use Rplus::DB;

use JSON;
use Mojo::Util qw(trim);
use Rplus::Util::PhoneNum;

sub list {
    my $self = shift;

    #return $self->render(json => {error => 'Method Not Allowed'}, status => 405) unless $self->req->method eq 'GET';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    # Not Implemented

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    # Retrieve client (by id or phone_num)
    my $client;
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    }
    elsif (my $phone_num = Rplus::Util::PhoneNum->parse(scalar $self->param('phone_num'))) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef])->[0];
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    my $metadata = decode_json($client->metadata);
    my $res = {
        id => $client->id,
        name => $client->name,
        phone_num => $client->phone_num,
        add_date => $self->format_datetime($client->add_date),
        description => $metadata->{description},
    };

    if ($self->param('with_subscriptions') eq 'true') {
        $res->{subscriptions} = [];

        # Retrieve client subscriptions including found realty count
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
            my $metadata = decode_json($row->{metadata});
            my $x = {
                id => $row->{id},
                client_id => $row->{client_id},
                user_id => $row->{user_id},
                offer_type_code => $row->{offer_type_code},
                queries => $row->{queries},
                add_date => $self->format_datetime($row->{add_date}),
                end_date => $self->format_datetime($row->{end_date}),
                realty_count => $row->{realty_count},
                realty_limit => $metadata->{realty_limit},
                send_seller_phone => $metadata->{send_seller_phone} ? \1 : \0,
            };
            push @{$res->{subscriptions}}, $x;
        }
    }

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    # Retrieve client
    my $client;
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $client = Rplus::Model::Client->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    # Validation
    $self->validation->required('phone_num')->is_phone;

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {phone_num => 'Invalid value'} if $self->validation->has_error('phone_num');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Prepare data
    my $name = $self->param('name'); $name = trim($name) || undef if defined $name;
    my $phone_num = $self->param('phone_num'); $phone_num = Rplus::Util::PhoneNum->parse($phone_num);
    my $description = $self->param('description') || undef;

    # Save
    my $metadata = decode_json($client->metadata || '{}');
    $client->name($name);
    $client->phone_num($phone_num);
    $metadata->{description} = $description;
    $client->metadata(encode_json($metadata));

    eval {
        $client->save($client->id ? (changes_only => 1) : (insert => 1));
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    return $self->render(json => {id => $client->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    my $id = $self->param('id');
    my $num_rows_updated = Rplus::Model::Client::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    return $self->render(json => {delete => \1});
}

sub subscribe {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    # Validation
    $self->validation->required('phone_num')->is_phone;
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
    my $phone_num = Rplus::Util::PhoneNum->parse(scalar $self->param('phone_num'));
    my $q = $self->param('q');
    my $offer_type_code = $self->param('offer_type_code');
    my $realty_ids = Mojo::Collection->new($self->param('realty_ids[]'))->compact->uniq;
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));

    # DB
    my $db = Rplus::DB->new_or_cached;
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
        user_id => $self->session->{'user'}->{'id'},
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

            # Подготовим СМС для _клиента_
            if ($phone_num =~ /^9\d{9}$/) {
                # TODO: Добавить настройки шаблонов
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->address_object->name !~ /[()]/ && $realty->sublandmark ? ' ('.$realty->sublandmark->name.')' : '') if $realty->address_object;
                    push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, decode_json($realty->agent->metadata)->{'public_name'} || $realty->agent->name if $realty->agent;
                    push @parts, decode_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num if $realty->agent;
                }
                my $sms_body = join(', ', @parts);
                my $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').($self->config->{subscription}->{contact_info} ? ' '.$self->config->{subscription}->{contact_info} : '');
                Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $sms_text, db => $db)->save;
            }

            # Подготовим СМС для _агента_
            if ($realty->agent && ($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                # TODO: Добавить настройки шаблонов
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, 'Клиент: '.($phone_num =~ s/^(\d{3})(\d{3})(\d{4})/($1) $2 $3/r);
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
