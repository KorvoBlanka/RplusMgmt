package RplusMgmt::Controller::API::Client;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Client;
use Rplus::Model::Client::Manager;

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

1;
