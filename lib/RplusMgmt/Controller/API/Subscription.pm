package RplusMgmt::Controller::API::Subscription;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;

sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'read');

    # Validation
    $self->validation->optional('date_from')->is_datetime;
    $self->validation->optional('date_to')->is_datetime;
    $self->validation->optional('offer_type_code')->in(qw(sale rent));
    $self->validation->optional('active')->in(qw(0 1 true false));
    $self->validation->optional('with_realty')->in(qw(0 1 true false));
    $self->validation->optional('client_id')->like(qr/^\d+$/);
    $self->validation->optional('phone_num')->is_phone_num;
    $self->validation->optional('skip_null_end_date')->in(qw(0 1 true false));

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {date_from => 'Invalid value'} if $self->validation->has_error('date_from');
        push @errors, {date_to => 'Invalid value'} if $self->validation->has_error('date_to');
        push @errors, {offer_type_code => 'Invalid value'} if $self->validation->has_error('offer_type_code');
        push @errors, {active => 'Invalid value'} if $self->validation->has_error('active');
        push @errors, {with_realty => 'Invalid value'} if $self->validation->has_error('with_realty');
        push @errors, {client_id => 'Invalid value'} if $self->validation->has_error('client_id');
        push @errors, {phone_num => 'Invalid value'} if $self->validation->has_error('phone_num');
        push @errors, {skip_null_end_date => 'Invalid value'} if $self->validation->has_error('skip_null_end_date');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Filters
    my $date_from = $self->parse_datetime(scalar $self->param('date_from'));
    my $date_to = $self->parse_datetime(scalar $self->param('date_to'));
    my $offer_type_code = $self->param('offer_type_code');
    my $active = $self->param_b('active');
    my $with_realty = $self->param_b('with_realty');
    my $client_id = $self->param('client_id');
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));
    my $skip_null_end_date = $self->param_b('skip_null_end_date');

    my @date_filter;
    if ($date_from && $date_to) {
        push @date_filter, add_date => {between => [$date_from, $date_to]};
    } elsif ($date_from) {
        push @date_filter, add_date => {ge => $date_from},
    } elsif ($date_to) {
        push @date_filter, add_date => {le => $date_to},
    }

    my $res = {
        count => 0,
        list => [],
    };

    # Load subscription data
    my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(
        query => [
            ($offer_type_code ? (offer_type_code => $offer_type_code) : ()),
            @date_filter,
            ($active ? (end_date => {gt => \'now()'}) : ()),
            delete_date => undef,
            ($client_id ? (client_id => $client_id) : ()),
            ($phone_num ? ('client.phone_num' => $phone_num) : ()),
            ($skip_null_end_date ? ('!end_date' => undef) : ()),
            'subscription_realty.delete_date' => undef,
        ],
        require_objects => ['client'],
        with_objects => ['subscription_realty'],
        sort_by => 'id',
    );
    my %realty_h;
    while (my $subscription = $subscription_iter->next) {
        my $x = {
            id => $subscription->id,
            client_id => $subscription->client_id,
            client => {
                id => $subscription->client->id,
                name => $subscription->client->name,
                phone_num => $subscription->client->phone_num,
            },
            queries => scalar $subscription->queries,
            add_date => $self->format_datetime($subscription->add_date),
            end_date => $self->format_datetime($subscription->end_date),
            realty_count => scalar @{$subscription->subscription_realty},
            realty_limit => $subscription->realty_limit,
            send_owner_phone => $subscription->send_owner_phone ? \1 : \0,
            realty => [],
        };
        push @{$res->{list}}, $x;

        for (@{$subscription->subscription_realty}) {
            $realty_h{$_->realty_id} = [] unless exists $realty_h{$_->realty_id};
            push @{$realty_h{$_->realty_id}}, $x;
        }
    }

    # Load realty data for subscriptions
    if ($with_realty && keys %realty_h) {
        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [id => [keys %realty_h]],
            with_objects => ['address_object', 'sublandmark'],
            sort_by => 'id',
        );
        while (my $realty = $realty_iter->next) {
            # TODO: Fix this (use serialize method)
            my $x = {
                id => $realty->id,
                type_code => $realty->type_code,
                offer_type_code => $realty->offer_type_code,
                house_num => $realty->house_num,
                rooms_count => $realty->rooms_count,
                rooms_offer_count => $realty->rooms_offer_count,
                price => $realty->price,
                agent_id => $realty->agent_id,

                address_object => $realty->address_object_id ? {
                    id => $realty->address_object->id,
                    name => $realty->address_object->name,
                    short_type => $realty->address_object->short_type,
                    expanded_name => $realty->address_object->expanded_name,
                    addr_parts => from_json($realty->address_object->metadata)->{'addr_parts'},
                } : undef,

                sublandmark => $realty->sublandmark ? {map { $_ => $realty->sublandmark->$_ } qw(id name)} : undef,
            };
            push @{$_->{realty}}, $x for @{$realty_h{$realty->id}};
        }
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'read');

    # Not Implemented

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $subscription;
    if (my $id = $self->param('id')) {
        $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $id, '!end_date' => undef, delete_date => undef])->[0];
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
    $self->validation->optional('send_owner_phone')->in(qw(0 1 true false));

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {client_id => 'Invalid value'} if $self->validation->has_error('client_id');
        push @errors, {offer_type_code => 'Invalid value'} if $self->validation->has_error('offer_type_code');
        push @errors, {end_date => 'Invalid value'} if $self->validation->has_error('end_date');
        push @errors, {realty_limit => 'Invalid value'} if $self->validation->has_error('realty_limit');
        push @errors, {send_owner_phone => 'Invalid value'} if $self->validation->has_error('send_owner_phone');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Prepare data
    my $client_id = $self->param('client_id');
    my $offer_type_code = $self->param('offer_type_code');
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));
    my $queries = Mojo::Collection->new($self->param('queries[]'))->map(sub { trim $_ })->compact->uniq;
    my $realty_limit = $self->param('realty_limit') || 0;
    my $send_owner_phone = $self->param_b('send_owner_phone');

    return $self->render(json => {errors => [{queries => 'Empty queries'}]}, status => 400) unless @$queries;

    # Save
    $subscription->client_id($client_id);
    $subscription->offer_type_code($offer_type_code);
    $subscription->queries($queries);
    $subscription->end_date($end_date);
    $subscription->realty_limit($realty_limit);
    $subscription->send_owner_phone($send_owner_phone);

    eval {
        $subscription->save($subscription->id ? (changes_only => 1) : (insert => 1));
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    return $self->render(json => {status => 'success', id => $subscription->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $id = $self->param('id');

    my $num_rows_updated = Rplus::Model::Subscription::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    return $self->render(json => {status => 'success'});
}

1;
