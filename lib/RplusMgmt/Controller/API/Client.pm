package RplusMgmt::Controller::API::Client;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::ClientColorTag::Manager;
use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Rplus::Util::Query;
use Rplus::Util::Task;

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;
use Time::Piece;


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
    my $subscription_offer_types = $self->param("subscription_offer_types") || 'any';
    my $subscription_rent_type = $self->param("subscription_rent_type") || 'any';
    my $color_tag_id = $self->param("color_tag_id") || 'any';
    my $agent_id = $self->param("agent_id") || 'any';
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;

    my $acc_id = $self->session('user')->{account_id};

    my $res = {
        count => 0,#Rplus::Model::Client::Manager->get_objects_count(query => [account_id => $acc_id, delete_date => undef]),
        list => [],
        page => $page,
    };

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
            push @query, 'client_color_tags.color_tag_id' => $color_tag_id;
            push @query, 'client_color_tags.user_id' => $self->stash('user')->{id};
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
            account_id => $acc_id,
            'subscriptions.offer_type_code' => $subscription_offer_types,
            #or => [
            #    subscription_offer_types => $subscription_offer_types,
            #    subscription_offer_types => 'both',
            #],
            @query,
            delete_date => undef,
        ],
        with_objects => ['client_color_tags', 'subscriptions'],
        sort_by => 'change_date desc',
        page => $page,
        per_page => $per_page,
    );

    while (my $client = $clients_iter->next) {
        my $phone_num = ' ';
        if (($client->agent_id && $client->agent_id == $self->stash('user')->{id}) || ($client->agent_id && $self->has_permission(clients => 'read')->{others}) || (!$client->agent_id && $self->has_permission(clients => 'read')->{nobody})) {
            $phone_num = $client->phone_num;
        }        
        my $x = {
            id => $client->id,
            add_date => $self->format_datetime($client->add_date),
            change_date => $self->format_datetime($client->change_date),
            name => $client->name,
            phone_num => $phone_num,
            email => $client->email,
            skype => $client->skype,
            description => $client->description,
            subscriptions => [],
            color_tag_id => 0,
            agent_id => $client->agent_id,
        };

        if($client->client_color_tags) {
            foreach ($client->client_color_tags) {
                if ($_->user_id == $self->stash('user')->{id}) {
                    $x->{color_tag_id} = $_->{color_tag_id};
                    last;
                }
            }
        }

        my @query; 
        {
            if ($subscription_rent_type ne 'any') {
                push @query, 'rent_type' => $subscription_rent_type;
            }
        }
        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(
            query => [
                @query,
                client_id => $client->id,
                offer_type_code => $subscription_offer_types,
                delete_date => undef,
                #'!end_date' => undef,
                #'subscription_realty.delete_date' => undef,
            ],
        );
        
        while (my $subscription = $subscription_iter->next) {
            my $sub = {
                id => $subscription->id,
                queries => scalar $subscription->queries,
                offer_type_code => $subscription->offer_type_code,
                rent_type => $subscription->rent_type,
                add_date => $self->format_datetime($subscription->add_date),
                end_date => $self->format_datetime($subscription->end_date),
                realty_count => scalar @{$subscription->subscription_realty},
                realty_limit => $subscription->realty_limit,
                send_owner_phone => $subscription->send_owner_phone ? \1 : \0,
            };
            push @{$x->{subscriptions}}, $sub;
        }
        push @{$res->{list}}, $x;
    }

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'read');
    
    # Retrieve client (by id or phone_num)
    my $acc_id = $self->session('user')->{account_id};

    my $client;
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef], with_objects => ['client_color_tags'],)->[0];
    } elsif (my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'))) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, phone_num => $phone_num, delete_date => undef], with_objects => ['client_color_tags'],)->[0];
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    my $phone_num = '';
    if (($client->agent_id && $client->agent_id == $self->stash('user')->{id}) || ($client->agent_id && $self->has_permission(clients => 'read')->{others}) || (!$client->agent_id && $self->has_permission(clients => 'read')->{nobody})) {
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

    if($client->client_color_tags) {
        foreach ($client->client_color_tags) {
            if ($_->user_id == $self->stash('user')->{id}) {
                $res->{color_tag_id} = $_->{color_tag_id};
                last;
            }
        }
    }
    
    if ($self->param_b('with_subscriptions')) {
        # Load subscription data
        $res->{subscriptions} = [];
        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(
            query => [
                client_id => $client->id,
                delete_date => undef,                
                #'!end_date' => undef,
            ],
            #require_objects => ['client'],
            #with_objects => ['subscription_realty'],
            sort_by => 'id',
        );
        my %realty_h;
        while (my $subscription = $subscription_iter->next) {
            my $x = {
                id => $subscription->id,
                offer_type_code => $subscription->offer_type_code,
                rent_type => $subscription->rent_type,
                queries => scalar $subscription->queries,
                add_date => $self->format_datetime($subscription->add_date),
                end_date => $self->format_datetime($subscription->end_date),
                #realty_count => scalar @{$subscription->subscription_realty},
                realty_limit => $subscription->realty_limit,
                send_owner_phone => $subscription->send_owner_phone ? \1 : \0,                
            };
            push @{$res->{subscriptions}}, $x;
        }
    }

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    # Retrieve client
    my $create_event = 0;
    my $client;
    my $acc_id = $self->session('user')->{account_id};
    if (my $id = $self->param('id')) {
        $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];
    } else {
        $client = Rplus::Model::Client->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write' => $client->agent_id) ||
                                                                                                        $client->agent_id == $self->stash('user')->{id} ||
                                                                                                        !$client->id && $self->param('agent_id') == $self->stash('user')->{id};

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
            $create_event = 1;
        }
    } else {
        $client->agent_id(undef);
    }

    $client->change_date('now()');
    
    eval {
        $client->save($client->id ? (changes_only => 1) : (insert => 1));
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    my $user_id = $self->stash('user')->{id};
    my $color_tag = Rplus::Model::ClientColorTag::Manager->get_objects(query => [client_id => $client->id, user_id => $user_id,])->[0];
    if ($color_tag) {
        if ($color_tag_id != $color_tag->color_tag_id) {
          $color_tag->color_tag_id($color_tag_id);
        } else {
          #$color_tag->color_tag_id(undef);
        }
        $color_tag->save(changes_only => 1);
    } else {
        $color_tag = Rplus::Model::ClientColorTag->new(
            client_id => $client->id,
            user_id => $user_id,
            color_tag_id => $color_tag_id,
        );
        $color_tag->save(insert => 1);
    }

    if ($create_event) {
        my $start_date = localtime;
        my $end_date = $start_date + 15 * 60;
        my $start_date_str = $start_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));
        my $end_date_str = $end_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));

        my @parts;
        {
            push @parts, $self->format_phone_num($client->phone_num) . ' ' . ($client->name ? $client->name : '');
        }
        my $summary = join(', ', @parts);

        Rplus::Util::Task::qcreate($self, {
                task_type_id => 11, # добавлен клиент
                assigned_user_id => $client->agent_id,
                start_date => $start_date_str,
                end_date => $end_date_str,
                summary => $summary,
                client_id => $client->id,
                realty_id => undef,
            });
    }

    return $self->render(json => {status => 'success', id => $client->id});
}

sub update {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write') || $client->agent_id == $self->stash('user')->{id};
    my $create_event = 0;

    # Retrieve client
    my $id = $self->param('id');
    my $acc_id = $self->session('user')->{account_id};
    my $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $client;

    my $permission_granted = $self->has_permission(clients => 'write');
    for ($self->param) {
        if ($_ eq 'agent_id') {
            my $agent_id = $self->param('agent_id');
            if ($agent_id) {
                if ($client->agent_id != $agent_id) {
                    $client->agent_id($agent_id);
                    $create_event = 1;
                }
            } else {
                $client->agent_id(undef);                
            }
        } elsif ($_ eq 'color_tag_id') {
            $permission_granted = 1;
            my $color_tag_id = $self->param('color_tag_id');
            my $user_id = $self->stash('user')->{id};
            my $color_tag = Rplus::Model::ClientColorTag::Manager->get_objects(query => [client_id => $client->id, user_id => $user_id,])->[0];
            if ($color_tag) {
                if ($color_tag_id != $color_tag->color_tag_id) {
                  $color_tag->color_tag_id($color_tag_id);
                } else {
                  #$color_tag->color_tag_id(undef);
                }
                $color_tag->save(changes_only => 1);
            } else {
                $color_tag = Rplus::Model::ClientColorTag->new(
                    client_id => $client->id,
                    user_id => $user_id,
                    color_tag_id => $color_tag_id,
                );
                $color_tag->save(insert => 1);
            }
        }
    }
    # Check that we can rewrite 
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $permission_granted;
    $client->save(changes_only => 1);

    if ($create_event) {
        my $start_date = localtime;
        my $end_date = $start_date + 15 * 60;
        my $start_date_str = $start_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));
        my $end_date_str = $end_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));

        my @parts;
        {
            push @parts, $self->format_phone_num($client->phone_num) . ' ' . ($client->name ? $client->name : '');
        }
        my $summary = join(', ', @parts);

        Rplus::Util::Task::qcreate($self, {
                task_type_id => 11, # добавлен клиент
                assigned_user_id => $client->agent_id,
                start_date => $start_date_str,
                end_date => $end_date_str,
                summary => $summary,
                client_id => $client->id,
                realty_id => undef,
            });
    }

    return $self->render(json => {status => 'success', id => $client->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'write');

    my $id = $self->param('id');
    my $acc_id = $self->session('user')->{account_id};

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

    my $acc_id = $self->session('user')->{account_id};

    # Input params
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));
    my $q = $self->param_n('q');
    my $offer_type_code = $self->param('offer_type_code');
    my $rent_type = $self->param('rent_type');
    my $realty_ids = Mojo::Collection->new($self->param('realty_ids[]'))->compact->uniq;
    my $end_date = $self->parse_datetime(scalar $self->param('end_date'));


    # Find/create client by phone number
    my $client = Rplus::Model::Client::Manager->get_objects(query => [account_id => $acc_id, phone_num => $phone_num, delete_date => undef])->[0];
    if (!$client) {
        $client = Rplus::Model::Client->new(account_id => $acc_id, phone_num => $phone_num);
    }

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(clients => 'subscribe') || $client->agent_id == $self->stash('user')->{id};

    $client->change_date('now()');
    $client->save;

    # Add subscription
    my $subscription = Rplus::Model::Subscription->new(
        client_id => $client->id,
        user_id => $self->session->{user}->{id},
        queries => [$q],
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
            with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
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
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->address_object->name !~ /[()]/ && $realty->sublandmark ? ' ('.$realty->sublandmark->name.')' : '') if $realty->address_object;
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
                my $start_date = localtime;
                my $end_date = $start_date + 15 * 60;
                my $start_date_str = $start_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));
                my $end_date_str = $end_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));

                my @parts;
                {
                    push @parts, $self->format_phone_num($phone_num) . ' ' . ($client->name ? $client->name : '');
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                }
                my $summary = join(', ', @parts);

                Rplus::Util::Task::qcreate($self, {
                        task_type_id => 10, # спрос
                        assigned_user_id => $realty->agent_id,
                        start_date => $start_date_str,
                        end_date => $end_date_str,
                        summary => $summary,
                        client_id => $client->id,
                        realty_id => $realty->id,
                    });
                if (($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
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
                    Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text, account_id => $acc_id)->save;
                }
            }
        }
    }

    return $self->render(json => {status => 'success'});
}

sub get_active_count {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

    my $offer_type_code = $self->param('offer_type_code');
    my $rent_type = $self->param('rent_type') || 'any';

    my $clients_count = 0;

    my @query;
    if ($self->stash('user')) {
        if ($self->stash('user')->{role} eq 'manger') {
            my $t = $self->stash('user')->{subordinate};
            push @{$t}, $self->stash('user')->{id};
            push @query, agent_id => $t;
        } elsif ($self->stash('user')->{role} eq 'agent' || $self->stash('user')->{role} eq 'agent_plus') {
            push @query, agent_id => $self->stash('user')->{id};
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
