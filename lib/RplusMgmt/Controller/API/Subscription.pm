package RplusMgmt::Controller::API::Subscription;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;

use Rplus::Util::Query;
use Rplus::Util::Realty;

no warnings 'experimental::smartmatch';

# Private function: serialize realty object(s)
my $_serialize = sub {
    my $self = shift;
    my @realty_objs = (ref($_[0]) eq 'ARRAY' ? @{shift()} : shift);
    my %params = @_;

    my @exclude_fields = qw(ap_num source_media_id source_media_text owner_phones work_info);
    my @exclude_fields_agent_plus = qw(ap_num source_media_text work_info);

    my (@serialized, %realty_h);
    for my $realty (@realty_objs) {

        my $x = {
            (map { $_ => ($_ =~ /_date$/ ? $self->format_datetime($realty->$_) : scalar($realty->$_)) } grep { !($_ ~~ [qw(delete_date geocoords landmarks metadata fts)]) } $realty->meta->column_names),
            
            address_object => $realty->address_object_id ? {
                id => $realty->address_object->id,
                name => $realty->address_object->name,
                short_type => $realty->address_object->short_type,
                expanded_name => $realty->address_object->expanded_name,
                addr_parts => from_json($realty->address_object->metadata)->{'addr_parts'},
            } : undef,

            color_tag_id => undef,
            
            sublandmark => $realty->sublandmark ? {id => $realty->sublandmark->id, name => $realty->sublandmark->name} : undef,

            main_photo_thumbnail => undef,
        };

        if($realty->color_tags) {
            foreach ($realty->color_tags) {
                if ($_->user_id == $self->stash('user')->{id}) {
                    $x->{color_tag_id} = $_->{color_tag_id};
                    last;
                }
            }
        }

        # Exclude fields for read permission "2"
        if ($self->has_permission(realty => read => $realty->agent_id) == 2) {
            $x->{$_} = undef for @exclude_fields;
        }

        # Exclude fields for read permission "3"
        if ($self->has_permission(realty => read => $realty->agent_id) == 3) {
            $x->{$_} = undef for @exclude_fields_agent_plus;
        }

        if ($params{with_sublandmarks}) {
            if (@{$realty->landmarks} || $realty->sublandmark_id) {
                my $sublandmarks = Rplus::Model::Landmark::Manager->get_objects(
                    select => 'id, name',
                    query => [
                        id => [@{$realty->landmarks}, $realty->sublandmark_id || ()],
                        type => 'sublandmark',
                        delete_date => undef,
                    ],
                    sort_by => 'name',
                );
                $x->{sublandmarks} = [map { {id => $_->id, name => $_->name} } @$sublandmarks];
            } else {
                $x->{sublandmarks} = [];
            }
        }

        push @serialized, $x;
        $realty_h{$realty->id} = $x;
    }

    # Fetch photos
    if (keys %realty_h) {
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [keys %realty_h], delete_date => undef], sort_by => 'is_main DESC, id ASC');
        while (my $photo = $photo_iter->next) {
            next if $realty_h{$photo->realty_id}->{main_photo_thumbnail};
            $realty_h{$photo->realty_id}->{main_photo_thumbnail} = $self->config->{'storage'}->{'url'}.'/photos/'.$photo->realty_id.'/'.$photo->thumbnail_filename;
        }
    }

    return @realty_objs == 1 ? $serialized[0] : @serialized;
};

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
            offer_type_code => $subscription->offer_type_code,
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

        for (@{$subscription->subscription_realty}) {
            $realty_h{$_->realty_id} = [] unless exists $realty_h{$_->realty_id};
            push @{$realty_h{$_->realty_id}}, $x;
        }

        push @{$res->{list}}, $x;
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

sub set_subscription_realty_state_code {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $realty_id = $self->param('realty_id');
    my $subscription_id = $self->param('subscription_id');
    my $state_code = $self->param('state_code');

    my $realty_record = Rplus::Model::SubscriptionRealty::Manager->get_objects(query => [realty_id => $realty_id, subscription_id => $subscription_id, delete_date => undef])->[0];

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty_record;

    if ($state_code eq 'del') {
        $realty_record->delete_date('now()');
    } else {
        $realty_record->state_code($state_code);
    }
    $realty_record->save();

    return $self->render(json => {status => 'success', id => $realty_record->id});
}

sub realty_list {
    my $self = shift;
    my $page = $self->param('page');
    my $per_page = $self->param('per_page');
    my $subscription_id = $self->param('subscription_id');

    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $subscription_id, delete_date => undef])->[0];
    update_subscription_realty($subscription);

    my $res = {
        count => Rplus::Model::SubscriptionRealty::Manager->get_objects_count(
            query => [subscription_id => $subscription->id, delete_date => undef],
            sort_by => 'state_code ASC',
            page => $page,
            per_page => $per_page,),
        list => [],
        state_list => [],
        page => $page,
        per_page => $per_page,
    };

    my $realty_objs = [];
    my $realty_id_iter = Rplus::Model::SubscriptionRealty::Manager->get_objects_iterator(
        query => [subscription_id => $subscription->id, delete_date => undef],
        sort_by => 'state_code ASC',
        page => $page,
        per_page => $per_page,);

    while (my $realty_id = $realty_id_iter->next) {

        my $realty = Rplus::Model::Realty::Manager->get_objects(
            query => [id => $realty_id->realty_id, delete_date => undef],
            with_objects => ['address_object', 'sublandmark', 'color_tags'],
            )->[0];

        my $x = {
            state_code => $realty_id->state_code,
        };
        push @{$res->{state_list}}, $x;
        push @{$realty_objs}, $realty;
    }

    $res->{list} = [$_serialize->($self, $realty_objs)];
    
    return $self->render(json => $res);    
}

sub update_subscription_realty {
    my $subscr = shift;

    for my $q (@{$subscr->queries}) {
        # Skip FTS data
        my @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } (Rplus::Util::Query->parse($q));

        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [
                offer_type_code => $subscr->offer_type_code,
                or => [
                  state_code => 'work',
                  state_code => 'raw',
                ],
                #or => [
                #    state_change_date => {gt => $subscr->add_date},
                #    price_change_date => {gt => ($subscr->last_check_date || $subscr->add_date)},
                #],
                [\"t1.id NOT IN (SELECT SR.realty_id FROM subscription_realty SR WHERE SR.subscription_id = ? AND SR.delete_date IS NULL)" => $subscr->id],
                delete_date => undef,
                @query
            ],
            with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
        );
        my $found = 0;
        while (my $realty = $realty_iter->next) {
            $found++;
            Rplus::Model::SubscriptionRealty->new(subscription_id => $subscr->id, realty_id => $realty->id)->save;
        }
    }

    $subscr->last_check_date('now()');
    $subscr->save(chages_only => 1);
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

    #my $realty_ids = Mojo::Collection->new($self->param('realty[]'))->compact->uniq;

    return $self->render(json => {errors => [{queries => 'Empty queries'}]}, status => 400) unless @$queries;

    # Save
    $subscription->client_id($client_id);
    $subscription->offer_type_code($offer_type_code);
    $subscription->queries($queries);
    $subscription->end_date($end_date);
    $subscription->realty_limit($realty_limit);
    $subscription->send_owner_phone($send_owner_phone);
    #$subscription->proposed_realty($realty_ids);
    
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
