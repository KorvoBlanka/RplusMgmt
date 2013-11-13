package RplusMgmt::Controller::API::Subscription;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;
use Rplus::Util::PhoneNum;

sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    # Not implemented (until finish Rplus::ORM)
    # This call is implemented in Client API

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    # Not Implemented

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub save {
    my $self = shift;

    my $subscription;
    if (my $id = $self->param('id')) {
        $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $id, '!end_date' => undef, delete_date => undef, \'t1.client_id = (SELECT C.id FROM clients C WHERE C.id = t1.client_id AND C.delete_date IS NULL)'])->[0];
    } else {
        $subscription = Rplus::Model::Subscription->new(user_id => $self->session->{user}->{id});
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $subscription;

    # Validation
    $self->validation->required('client_id')->like(qr/^\d+$/);
    $self->validation->required('offer_type_code')->in(qw(sale rent));
    $self->validation->required('end_date')->is_datetime;
    #$self->validation->required('queries[]');
    $self->validation->optional('realty_limit')->like(qr/^\d+$/);
    $self->validation->optional('send_seller_phone')->in(qw(true false));

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {client_id => 'Invalid value'} if $self->validation->has_error('client_id');
        push @errors, {offer_type_code => 'Invalid value'} if $self->validation->has_error('offer_type_code');
        push @errors, {end_date => 'Invalid value'} if $self->validation->has_error('end_date');
        push @errors, {realty_limit => 'Invalid value'} if $self->validation->has_error('realty_limit');
        push @errors, {send_seller_phone => 'Invalid value'} if $self->validation->has_error('send_seller_phone');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Prepare data
    my $client_id = $self->param('client_id');
    my $offer_type_code = $self->param('offer_type_code');
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));
    my @queries = Mojo::Collection->new($self->param('queries[]'))->map(sub { trim $_ })->compact->uniq;
    my $realty_limit = $self->param('realty_limit') || undef;
    my $send_seller_phone = $self->param('send_seller_phone') || 'false';

    return $self->render(json => {errors => [{queries => 'Empty queries'}]}, status => 400) unless @queries;

    # Save
    my $metadata = decode_json($subscription->metadata || '{}');
    $subscription->client_id($client_id);
    $subscription->offer_type_code($offer_type_code);
    $subscription->queries(\@queries);
    $subscription->end_date($end_date);
    $metadata->{realty_limit} = $realty_limit;
    $metadata->{send_seller_phone} = $send_seller_phone eq 'false' ? JSON::false : JSON::true;
    $subscription->metadata(encode_json($metadata));

    eval {
        $subscription->save($subscription->id ? (changes_only => 1) : (insert => 1));
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    return $self->render(json => {id => $subscription->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->stash('controller_role_conf')->{$self->stash('action')};

    my $id = $self->param('id');
    my $num_rows_updated = Rplus::Model::Subscription::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    return $self->render(json => {delete => \1});
}

1;
