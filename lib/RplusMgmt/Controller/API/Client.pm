package RplusMgmt::Controller::API::Client;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::Option::Manager;

use Rplus::Util::Query;
use Rplus::Util::Task;

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;
use Time::Piece;

use Data::Dumper;

my $_serialize = sub {
    my $self = shift;
    my ($client, $with_subscriptions, $subscription_offer_type, $subscription_rent_type) = @_;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $phone_num = '';
    if (($client->agent_id && $client->agent_id == $user_id) ||
          ($client->agent_id && $self->has_permission(clients => 'read')->{others}) ||
              (!$client->agent_id && $self->has_permission(clients => 'read')->{nobody})) {
        $phone_num = $client->phone_num;
    }
    my $res = {
        id => $client->id,
        name => $client->name,
        phone_num => $phone_num,
        email => $client->email,
        skype => $client->skype,
        add_date => $self->format_datetime($client->add_date),
        change_date => $self->format_datetime($client->change_date),
        description => $client->description,
        send_owner_phone => $client->send_owner_phone,
        color_tag_id => 0,
        agent_id => $client->agent_id,
    };

    if ($client->color_tag) {
        my $ct = Mojo::Collection->new(@{$client->color_tag});
        my $tag_prefix = $user_id . '_';
        $ct = $ct->grep(sub {
            $_ =~ /$tag_prefix/;
        });
        my $t = $ct->first;
        $t =~ s/^\d+?_//;
        $res->{color_tag_id} = $t;
    }

    if ($with_subscriptions) {
        # Load subscription data
        $res->{subscriptions} = [];

        my @query;
        if ($subscription_offer_type && $subscription_offer_type ne 'any') {
            push @query, 'offer_type_code' => $subscription_offer_type;
            if ($subscription_rent_type && $subscription_rent_type ne 'any') {
                push @query, 'rent_type' => $subscription_rent_type;
            }
        }
        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(
            query => [
                @query,
                client_id => $client->id,
                delete_date => undef,
                #'!end_date' => undef,
                #'subscription_realty.delete_date' => undef,
            ],
            sort_by => 'id',
        );

        my %realty_h;
        while (my $subscription = $subscription_iter->next) {
            my $x = {
                id => $subscription->id,
                offer_type_code => $subscription->offer_type_code,
                rent_type => $subscription->rent_type,
                queries => scalar $subscription->queries,
                search_area => $subscription->search_area,
                add_date => $self->format_datetime($subscription->add_date),
                end_date => $self->format_datetime($subscription->end_date),
                #realty_count => scalar @{$subscription->subscription_realty},
                realty_limit => $subscription->realty_limit,
                send_owner_phone => $subscription->send_owner_phone ? \1 : \0,
            };
            push @{$res->{subscriptions}}, $x;
        }
    }
    return $res;
};

sub list {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'read');

    # Input validation
    $self->validation->optional('page')->like(qr/^\d+$/);
    $self->validation->optional('per_page')->like(qr/^\d+$/);

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {page => 'Invalid value'} if $self->validation->has_error('page');
        push @errors, {per_page => 'Invalid value'} if $self->validation->has_error('per_page');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Input params
    my $subscription_offer_type = $self->param("subscription_offer_types") || 'any';
    my $subscription_rent_type = $self->param("subscription_rent_type") || 'any';
    my $color_tag_id = $self->param("color_tag_id") || 'any';
    my $agent_id = $self->param("agent_id") || 'any';
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my @query;
    {
        if ($agent_id ne 'any') {
            if ($agent_id eq 'nobody') {
                push @query, 'agent_id' => undef;
            } elsif ($agent_id eq 'all') {
                push @query, '!agent_id' => undef;
            } elsif ($agent_id =~ /^\d+$/) {
                push @query, 'agent_id' => $agent_id;
            }
        }
        if ($color_tag_id ne 'any') {
            my $tag = $user_id . '_' . $color_tag_id;
            push @query, \("color_tag && '{$tag}'");
        }
        if ($subscription_offer_type ne 'any') {
            push @query, 'subscriptions.offer_type_code' => $subscription_offer_type;
        }
        if ($subscription_rent_type ne 'any') {
            push @query, 'subscriptions.rent_type' => $subscription_rent_type;
        }
    }

    my $clients_iter = Rplus::Model::Client::Manager->get_objects_iterator(
        select => [
            'clients.*',
        ],
        query => [
            @query,
            account_id => $acc_id,
            delete_date => undef,
        ],
        with_objects => ['subscriptions'],
        sort_by => 'change_date desc',
        page => $page,
        per_page => $per_page,
    );

    my $res = {
        count => 0,#Rplus::Model::Client::Manager->get_objects_count(query => [account_id => $acc_id, delete_date => undef]),
        list => [],
        page => $page,
    };

    while (my $client = $clients_iter->next) {
        push @{$res->{list}}, $_serialize->($self, $client, 1, $subscription_offer_type, $subscription_rent_type);
    }

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'read');

    # Retrieve client (by id or phone_num)
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};
    my $with_subscriptions = $self->param_b('with_subscriptions');

    my $client;
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef],)->[0];
    } elsif (my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'))) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, phone_num => $phone_num, delete_date => undef],)->[0];
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    my $res = $_serialize->($self, $client, $with_subscriptions);

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    # Retrieve client
    my $client;
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];
    } else {
        $client = Rplus::Model::Client->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;
    return $self->render(json => {error => 'Forbidden'}, status => 403)
        unless
            $self->has_permission(clients => 'write' => $client->agent_id) ||
            $client->agent_id == $user_id ||
            !$client->id && $self->param('agent_id') == $user_id;

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
    my $email = $self->param_n('email');
    my $skype = $self->param_n('skype');
    my $description = $self->param_n('description');
    my $send_owner_phone = $self->param_b('send_owner_phone');
    my $color_tag_id = $self->param('color_tag_id');
    my $agent_id = $self->param('agent_id');

    # Save
    $client->name($name);
    $client->phone_num($phone_num);
    $client->email($email);
    $client->skype($skype);
    $client->description($description);
    $client->send_owner_phone($send_owner_phone);
    $client->account_id($acc_id);

    unless ($self->has_permission(clients => 'write' => $client->agent_id)) {
        #$agent_id = $self->stash('user')->{id};
    }

    if ($agent_id) {
        if ($client->agent_id != $agent_id) {
            $client->agent_id($agent_id);
        }
    } else {
        $client->agent_id(undef);
    }

    # Color tag
    my $ct = Mojo::Collection->new();
    if ($client->color_tag) {
        $ct = Mojo::Collection->new(@{$client->color_tag});
    }
    my $tag_prefix = $user_id . '_';
    if ($color_tag_id) {
        $ct = $ct->grep(sub {   # remove all user tags
            $_ !~ /$tag_prefix/;
        });
        my $tag = $tag_prefix . $color_tag_id;
        push @$ct, $tag;        # add new
    } else {
        $ct = $ct->grep(sub {
            $_ !~ /$tag_prefix/;
        });
    }
    $client->color_tag($ct);

    $client->change_date('now()');

    eval {
        $client->save($client->id ? (changes_only => 1) : (insert => 1));
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    return $self->render(json => {status => 'success', id => $client->id});
}

sub update {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write') || $client->agent_id == $self->stash('user')->{id};

    # Retrieve client
    my $id = $self->param('id');
    my $agent_id = $self->param('agent_id');
    my $color_tag_id = $self->param('color_tag_id');


    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    my $permission_granted = $self->has_permission(clients => 'write');

    if (defined $agent_id) {
        if ($agent_id) {
            if ($client->agent_id != $agent_id) {
                $client->agent_id($agent_id);
            }
        } else {
            $client->agent_id(undef);
        }
    }
    if (defined $color_tag_id) {
        $permission_granted = 1;

        my $ct = Mojo::Collection->new();
        if ($client->color_tag) {
            $ct = Mojo::Collection->new(@{$client->color_tag});
        }
        my $tag_prefix = $user_id . '_';
        my $tag = $tag_prefix . $color_tag_id;
        if ($ct->first(qr/$tag/)) {   # remove tag
            $ct = $ct->grep(sub {
                $_ !~ /$tag/;
            });
        } else {                       # add tag
            $ct = $ct->grep(sub {
                $_ !~ /$tag_prefix/;
            });
            push @$ct, $tag;
        }
        $client->color_tag($ct->uniq);

    }

    # Check that we can rewrite
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $permission_granted;
    $client->save(changes_only => 1);

    return $self->render(json => {status => 'success', id => $client->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write');

    my $id = $self->param('id');
    my $acc_id = $self->session('account')->{id};

    # Удалим подписки
    my $num_rows_updated = Rplus::Model::Subscription::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [client_id => $id, delete_date => undef],
    );

    # Удалим клиента
    $num_rows_updated = Rplus::Model::Client::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [account_id => $acc_id, id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    # Не удаляем недвижимость на этой подписке?

    return $self->render(json => {status => 'success'});
}

sub subscribe {
    my $self = shift;

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

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    # Input params
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));
    my $q = $self->param_n('q');
    my $search_area = $self->param_n('search_area');
    my $offer_type_code = $self->param('offer_type_code');
    my $rent_type = $self->param('rent_type');
    my $realty_ids = Mojo::Collection->new(@{$self->every_param('realty_ids[]')})->compact->uniq;
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));


    # Find/create client by phone number
    my $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, phone_num => $phone_num, delete_date => undef])->[0];
    if (!$client) {
        $client = Rplus::Model::Client->new(account_id => $acc_id, phone_num => $phone_num);
    }

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'subscribe') || $client->agent_id == $user_id;

    $client->change_date('now()');
    $client->save;

    # Add subscription
    my $subscription = Rplus::Model::Subscription->new(
        client_id => $client->id,
        user_id => $user_id,
        queries => [$q],
        search_area => $search_area,
        offer_type_code => $offer_type_code,
        rent_type => $rent_type,
        end_date => $end_date,
    );
    $subscription->save;

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $contact_info = '';
    if ($options) {
        my $n_opt = from_json($options->{options})->{'notifications'};
        $contact_info = $n_opt->{'contact_info'} ? $n_opt->{'contact_info'} : '';
    }
    # Add realty to subscription & generate SMS
    for my $realty_id (@$realty_ids) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            query => [id => $realty_id, state_code => ['work',], offer_type_code => $offer_type_code],
            with_objects => ['agent', 'type'],
        )->[0];
        if ($realty) {
            Rplus::Model::SubscriptionRealty->new(subscription_id => $subscription->id, realty_id => $realty->id, offered => 'true')->save;

            # Prepare SMS for client
            if ($phone_num =~ /^9\d{9}$/) {
                # TODO: Add template settings
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->locality.', '.$realty->address if $realty->address && $realty->locality;
                    push @parts, $realty->district if $realty->district;
                    push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, $realty->agent->public_name || $realty->agent->name if $realty->agent;
                    push @parts, $realty->agent->public_phone_num || $realty->agent->phone_num if $realty->agent;
                }
                my $sms_body = join(', ', @parts);
                my $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').$contact_info;
                Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $sms_text, account_id => $acc_id)->save;
            }

            if ($realty->agent) {
                if (($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                    # TODO: Add template settings
                    my @parts;
                    {
                        push @parts, $realty->type->name;
                        push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                        push @parts, $realty->locality.', '.$realty->address.' '.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address && $realty->locality;
                        push @parts, $realty->price.' тыс. руб.' if $realty->price;
                        push @parts, 'Клиент: '.$self->format_phone_num($phone_num);
                    }
                    my $sms_text = join(', ', @parts);
                    Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text, account_id => $acc_id)->save;
                }
            }
        }
    }

    return $self->render(json => {status => 'success'});
}

sub get_active_count {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $offer_type_code = $self->param('offer_type_code');
    my $rent_type = $self->param('rent_type') || 'any';

    my $clients_count = 0;

    my @query;
    if ($self->stash('user')) {
        if ($self->stash('user')->{role} eq 'manger') {
            my $t = $self->stash('user')->{subordinate};
            push @{$t}, $user_id;
            push @query, agent_id => $t;
        } elsif ($self->stash('user')->{role} eq 'agent' || $self->stash('user')->{role} eq 'agent_plus') {
            push @query, agent_id => $user_id;
        }

        if ($rent_type ne 'any') {
            push @query, 'rent_type' => $rent_type;
        }
    }

    my $sub_iter = Rplus::Model::Subscription::Manager->get_objects_iterator (
        query => [
            @query,
            'client.account_id' => $acc_id,
            offer_type_code => $offer_type_code,
            end_date => {gt => \'now()'},
            delete_date => undef,
        ],
        with_objects => ['client'],
    );

    my %clients;
    while (my $sub = $sub_iter->next) {
        $clients{$sub->client->id} = 1;
    }

    return $self->render(json => {status => 'success', client_count => scalar keys %clients});
}

1;
