package RplusMgmt::Controller::API::Subscription;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Photo::Manager;

use Rplus::Model::Mediator::Manager;
use Rplus::Model::Client::Manager;
use Rplus::Model::Option::Manager;

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;
use Date::Parse;

use Rplus::Util::History qw(subscription_record notification_record);
use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::SMS qw(prepare_sms_text enqueue send_sms);


no warnings 'experimental::smartmatch';

# Private function: serialize realty object(s)
my $_serialize = sub {
    my $self = shift;
    my $ff = shift;
    my @realty_objs = (ref($_[0]) eq 'ARRAY' ? @{shift()} : shift);
    my %params = @_;

    my @exclude_fields = qw(ap_num source_media_id source_media_text owner_phones work_info reference);

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my (@serialized, %realty_h);
    for my $realty (@realty_objs) {

        my $company = '';
        if ($realty->account_id && $realty->account_id != $acc_id) {
            $company = '';
        } else {
            my $a = $realty->owner_phones;
            if (scalar @{$a}) {
                my $x = Rplus::Model::Mediator::Manager->get_objects(
                    query => [
                        phone_num => [@{$a}],
                        delete_date => undef,
                        or => [account_id => undef, account_id => $acc_id],
                        \("NOT t1.hidden_for_aid && '{".$acc_id."}'"),
                    ],
                    require_objects => ['company'],
                    limit => 1,
                )->[0];
                if ($x) {
                    $company = $x->company->name;
                }
            }
        }

        my $x = {
            (map { $_ => ($_ =~ /_date$/ ? $self->format_datetime($realty->$_) : scalar($realty->$_)) } grep { !($_ ~~ [qw(landmarks sublandmark_id address_object_id delete_date geocoords landmarks metadata fts)]) } $realty->meta->column_names),
            color_tag_id => undef,
            main_photo_thumbnail => undef,
            mediator_company => $company,
            reference => '',
            sr_state_code => $realty->{sr_state_code},
            sr_offered => $realty->{sr_offered},
        };

        if ($realty->color_tag) {
            my $ct = Mojo::Collection->new(@{$realty->color_tag});
            my $tag_prefix = $user_id . '_';
            $ct = $ct->grep(sub {
                $_ =~ /$tag_prefix/;
            });
            my $t = $ct->first;
            $t =~ s/^\d+?_//;
            $x->{color_tag_id} = $t;
        }

        # Exclude fields for read permission "2"
        if ($self->has_permission(realty => read => $realty->agent_id) == 2 && !($realty->agent_id ~~ @{$self->stash('user')->{subordinate}})) {
            $x->{$_} = undef for @exclude_fields;
            if ($realty->agent_id) {
                my $user = Rplus::Model::User::Manager->get_objects(query => [id => $realty->agent_id, delete_date => undef])->[0];
                $x->{owner_phones} = [$user->public_phone_num];
            }
        }

        # if it's a demo acc - hide refs and phones
        if ($self->account_type() eq 'demo') {
            $x->{reference} = '';
            $x->{owner_phones} = ['ДЕМО ВЕРСИЯ'];
        }

        if ($ff eq 'not_med') {
            $x->{mediator_company} = '';
        } elsif ($ff eq 'med' && !$x->{mediator_company}) {
            $x->{mediator_company} = 'ПОСРЕДНИК В НЕДВИЖИМОСТИ';
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

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'read');

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
    my $rent_type = $self->param('rent_type');
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
            rent_type => $subscription->rent_type,
            client => {
                id => $subscription->client->id,
                name => $subscription->client->name,
                phone_num => $subscription->client->phone_num,
            },
            queries => scalar $subscription->queries,
            search_area => $subscription->search_area,
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

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'read');

    # Not Implemented

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub realty_set_state {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $realty_id = $self->param('realty_id');
    my $subscription_id = $self->param('subscription_id');
    my $state_code = $self->param('state_code');

    my $realty_record = Rplus::Model::SubscriptionRealty::Manager->get_objects(query => [realty_id => $realty_id, subscription_id => $subscription_id])->[0];

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty_record;

    $realty_record->state_code($state_code);
    $realty_record->save(changes_only => 1);

    return $self->render(json => {status => 'success', id => $realty_record->id});
}

sub realty_clear_list {
    my $self = shift;
    my $subscription_id = $self->param('subscription_id');

    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $subscription_id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $subscription;

    Rplus::Model::SubscriptionRealty::Manager->delete_objects(
        where => [
            subscription_id => $subscription_id,
        ],
    );

    return $self->render(json => {status => 'success'});
}

sub realty_list {
    my $self = shift;

    my $depth = $self->param('depth') || 'full';
    my $page = $self->param('page');
    my $per_page = $self->param('per_page');
    my $subscription_id = $self->param('subscription_id');

    my $state_code = $self->param("state_code") || 'any';
    my $agent_id = $self->param("agent_id") || 'any';
    my $color_tag_id = $self->param("color_tag_id") || 'any';
    my $realty_state_code = $self->param("state_code") || 'any';
    my $sr_state_code = $self->param("sr_state_code") || 'any';
    my $sr_offered = $self->param("sr_offered") || 'any';

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $ff = '';

    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $subscription_id, delete_date => undef])->[0];
    if ($page eq '1') {
        realty_update($self, $subscription->id);
    }

    my @query;
    {
        push @query, 'subscription_id' => $subscription->id;

        if ($depth ne 'full') {
            push @query, \("t2.last_seen_date > now() - interval '$depth days'");
        }

        if ($sr_state_code ne 'any') {
            push @query, 'state_code' => $sr_state_code;
        }
        if ($sr_offered ne 'any') {
            if ($sr_offered eq '1' || $sr_offered eq 'true' || $sr_offered eq 'TRUE') {
                push @query, 'offered' => 1;
            } else {
                push @query, 'offered' => 0;
            }
        }
        if ($agent_id ne 'any') {
            if ($agent_id eq 'all' && $self->has_permission(realty => 'read')->{others}) {
                push @query, and => ['!realty.agent_id' => undef, '!realty.agent_id' => 10000];
            } elsif ($agent_id eq 'not_med') {
                $ff = 'not_med';
                push @query, agent_id => undef;
                push @query, 'realty.mediator_company_id' => undef;
                #push @query,
                    #[\"NOT EXISTS (SELECT 1 FROM mediators WHERE mediators.phone_num = ANY (t3.owner_phones) AND mediators.delete_date IS NULL AND ((mediators.account_id IS NULL AND NOT mediators.hidden_for_aid && '{4}') OR mediators.account_id = 4) LIMIT 1)"];

            } elsif ($agent_id eq 'med') {
                $ff = 'med';
                push @query, '!realty.mediator_company_id' => undef;
                #push @query,
                    #[\"EXISTS (SELECT 1 FROM mediators WHERE mediators.phone_num = ANY (t3.owner_phones) AND mediators.delete_date IS NULL AND ((mediators.account_id IS NULL AND NOT mediators.hidden_for_aid && '{4}') OR mediators.account_id = 4) LIMIT 1)"];

            } elsif ($agent_id =~ /^a(\d+)$/) {
                my $manager = Rplus::Model::User::Manager->get_objects(query => [id => $1, delete_date => undef])->[0];
                if (scalar (@{$manager->subordinate})) {
                    push @query, 'realty.agent_id' => [$manager->subordinate];
                } else {
                    push @query, 'realty.agent_id' => 0;
                }
            } elsif ($agent_id =~ /^\d+$/ && $self->has_permission(realty => read => $agent_id)) {
                push @query, 'realty.agent_id' => $agent_id;
            }


        }

        if ($color_tag_id ne 'any') {
            my $tag = $user_id . '_' . $color_tag_id;
            push @query, \("t2.color_tag && '{$tag}'");
        }

        if ($state_code ne 'any') {
            push @query, 'realty.state_code' => $state_code;
        } else {
            push @query, '!realty.state_code' => 'deleted';
        }
        push @query, or => ['realty.account_id' => undef, 'realty.account_id' => $acc_id];
        #push @query, \("NOT realty.hidden_for && '{".$acc_id."}'");
    }

    my $res = {
        count => 0,
        list => [],
        page => $page,
        per_page => $per_page,
    };

    $res->{count} = Rplus::Model::SubscriptionRealty::Manager->get_objects_count(
        query => [
            @query,
            '!state_code' => 'del',
        ],
        require_objects => ['realty'],
    );

    my $realty_iter = Rplus::Model::SubscriptionRealty::Manager->get_objects_iterator(
        select => ['subscription_realty.id', 'subscription_realty.state_code', 'subscription_realty.offered', 'realty.*'],
        query => [
            @query,
            '!state_code' => 'del',
        ],
        with_objects => ['realty'],
        sort_by => 'subscription_realty.state_code ASC, realty.last_seen_date DESC',
        page => $page,
        per_page => $per_page,
    );

    my $realty_objs = [];
    while (my $realty = $realty_iter->next) {
        $realty->realty->{sr_state_code} = $realty->state_code;
        $realty->realty->{sr_offered} = $realty->offered;
        push @{$realty_objs}, $realty->realty;
        if ($realty->state_code eq 'new') {
            $realty->state_code('old');
            $realty->save(changes_only => 1);
        }
    }

    $res->{list} = [$_serialize->($self, $ff, $realty_objs)];

    return $self->render(json => $res);
}

sub realty_update {
    my ($self, $subscription_id) = @_;
    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $subscription_id, delete_date => undef])->[0];

    my $acc_id = $self->session('account')->{id};

    for my $q (@{$subscription->queries}) {
        # Skip FTS data
        my @query = Rplus::Util::Query::parse($q, $self);

        if ($subscription->search_area) {
          push @query, \("postgis.st_covers(postgis.ST_GeomFromEWKT('SRID=4326;" . $subscription->search_area . "')::postgis.geography, t1.geocoords)");
        }

        my @types;
        if (1 != 2) {
            my $offer_type_code = $subscription->offer_type_code;
            my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
            my $opt = from_json($options->{options});
            my $import = $opt->{import};

            while (my ($key, $value) = each %{$import}) {
                if ($key =~ /$offer_type_code-(\w+)/ && ($value eq 'true' || $value eq '1')) {
                    push @types, $1;
                }
            }
            if (scalar @types) {
                push @query, 'type_code' => \@types ;
            } else {
                push @query, 'type_code' => 'none';
            }
        }

        if ($subscription->rent_type) {
            push @query, rent_type => $subscription->rent_type;
        }

        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [
                @query,
                offer_type_code => $subscription->offer_type_code,
                delete_date => undef,
                state_code => ['work', 'raw', 'suspended'],
                or => [account_id => undef, account_id => $acc_id],
                \("NOT hidden_for && '{".$acc_id."}'"),
                [\"t1.id NOT IN (SELECT SR.realty_id FROM subscription_realty SR WHERE SR.subscription_id = ?)" => $subscription->id],
            ],
        );

        my $values_str = '';
        my $sid = $subscription->id;
        while (my $realty = $realty_iter->next) {
            #Rplus::Model::SubscriptionRealty->new(subscription_id => $subscription->id, realty_id => $realty->id)->save;
            my $realty_id = $realty->id;
            $values_str .= "($sid, $realty_id),";
        }
        if (length $values_str > 0) {
            chop $values_str;
            Rplus::DB->new_or_cached->dbh->do("INSERT INTO subscription_realty (subscription_id, realty_id) VALUES $values_str;");
        }
    }
}

sub update {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $id = $self->param('id');
    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $subscription;

    my $queries = Mojo::Collection->new(@{$self->every_param('queries[]')})->map(sub { trim $_ })->compact->uniq;
    $subscription->queries($queries);
    $subscription->add_date('now()');

    if (str2time($subscription->end_date) <= time()) {
        $subscription->end_date(undef);
    }

    $subscription->save(changes_only => 1);

    my $num_del = Rplus::Model::SubscriptionRealty::Manager->delete_objects(
        where => [
            subscription_id => $subscription->id,
        ],
    );
    realty_update($self, $subscription->id);

    return $self->render(json => {status => 'success', id => $subscription->id, del => $num_del});
}

sub save {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $subscription;
    if (my $id = $self->param('id')) {
        $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $subscription = Rplus::Model::Subscription->new(user_id => $self->stash('user')->{id});
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $subscription;

    # Validation
    $self->validation->required('client_id')->like(qr/^\d+$/);
    $self->validation->required('offer_type_code')->in(qw(sale rent));
    $self->validation->optional('end_date')->is_datetime;
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
    my $rent_type = $self->param('rent_type');
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));
    my $queries = Mojo::Collection->new(@{$self->every_param('queries[]')})->map(sub { trim $_ })->compact->uniq;
    my $realty_limit = $self->param('realty_limit') || 20;
    my $send_owner_phone = $self->param_b('send_owner_phone');
    my $realty_ids = Mojo::Collection->new(@{$self->every_param('realty_ids[]')})->compact->uniq;

    return $self->render(json => {errors => [{queries => 'Empty queries'}]}, status => 400) unless @$queries;

    if ($subscription->id) {
        subscription_record($acc_id, $user_id, 'update', $subscription, {
            client_id => $client_id,
            offer_type_code => $offer_type_code,
            rent_type => $rent_type,
            queries => $queries,
            end_date => $end_date,
            realty_limit => $realty_limit,
            send_owner_phone => $send_owner_phone,
        });
    }

    # Save
    $subscription->client_id($client_id);
    $subscription->offer_type_code($offer_type_code);
    $subscription->rent_type($rent_type);
    $subscription->queries($queries);
    $subscription->end_date($end_date);
    $subscription->realty_limit($realty_limit);
    $subscription->send_owner_phone($send_owner_phone);

    $subscription->add_date('now()');

    if (str2time($subscription->end_date) <= time()) {
        $subscription->end_date(undef);
    }

    eval {
        if ($subscription->id) {
            $subscription->save(changes_only => 1);
        } else {
            subscription_record($acc_id, $user_id, 'add', $subscription, undef);
            $subscription->save(insert => 1);
        }
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    # Find by phone number/create client
    my $client = Rplus::Model::Client::Manager->get_objects(query => [id => $client_id, delete_date => undef])->[0];
    if (!$client) {
        return $self->render(json => {error => 'Not Found'}, status => 404) unless $subscription;
    }
    $client->change_date('now()');
    $client->save;

    for my $realty_id (@$realty_ids) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            query => [
                id => $realty_id,
                state_code => ['raw', 'suspended'],
                offer_type_code => $offer_type_code,
            ],
        )->[0];
        if ($realty) {
            Rplus::Model::SubscriptionRealty->new(subscription_id => $subscription->id, realty_id => $realty->id, state_code => 'attention')->save;
        }
    }

    # Add realty to subscription & generate SMS
    for my $realty_id (@$realty_ids) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            query => [id => $realty_id],
            with_objects => ['agent', 'type'],
        )->[0];
        if ($realty) {
            Rplus::Model::SubscriptionRealty->new(subscription_id => $subscription->id, realty_id => $realty->id, offered => 'true')->save;

            # Prepare SMS for client
            if ($client->phone_num =~ /^9\d{9}$/) {
                my $sms_text = prepare_sms_text($realty, 'CLIENT', $client, $acc_id);
                my $sms = enqueue($client->phone_num, $sms_text, $acc_id);
                notification_record($acc_id, $user_id, 'sms_enqueued', $sms);
            }

            # Prepare SMS for agent
            if ($realty->agent && ($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                my $sms_text = prepare_sms_text($realty, 'AGENT', $client, $acc_id);
                my $sms = enqueue($realty->agent->phone_num, $sms_text, $acc_id);
                notification_record($acc_id, $user_id, 'sms_enqueued', $sms);
            }
        }
    }

    return $self->render(json => {status => 'success', id => $subscription->id});
}

sub delete {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $id = $self->param('id');
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $subscription;
    $subscription->delete_date('now()');
    $subscription->save;

    subscription_record($acc_id, $user_id, 'add', $subscription, undef);

    return $self->render(json => {status => 'success'});
}

sub get_active_count {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};

    my $offer_type_code = $self->param('offer_type_code') || 'none';

    my $clients_count = 0;

    my @query;
    if ($self->stash('user')) {
        if ($self->stash('user')->{role} eq 'manger') {
            my $t = $self->stash('user')->{subordinate};
            push @{$t}, $self->stash('user')->{id};
            push @query, user_id => $t;
        } elsif ($self->stash('user')->{role} eq 'agent' || $self->stash('user')->{role} eq 'agent_plus') {
            push @query, user_id => $self->stash('user')->{id};
        }
    }

    my $sub_count = Rplus::Model::Subscription::Manager->get_objects_count (
        query => [
            @query,
            'user.account_id' => $acc_id,
            offer_type_code => $offer_type_code,
            end_date => {gt => \'now()'},
            delete_date => undef,
        ],
        with_objects => ['user'],
    );

    return $self->render(json => {status => 'success', sub_count => $sub_count});
}

1;
