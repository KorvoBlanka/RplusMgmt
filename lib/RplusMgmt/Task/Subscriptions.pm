package RplusMgmt::Task::Subscriptions;

use Rplus::Modern;

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Rplus::Util::Query;
use JSON;

sub run {
    my $c = shift;

    my $account_iter = Rplus::Model::Account::Manager->get_objects_iterator(query => [del_date => undef]);
    while (my $account = $account_iter->next) {

        my $acc_id = $account->id;
        my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
        my $contact_info = '';
        if ($options) {
            my $config = from_json($options->{options})->{'notifications'};
            $contact_info = $config->{'contact_info'} ? $config->{'contact_info'} : '';
        }

        my $clients_iter = Rplus::Model::Client::Manager->get_objects_iterator(
            query => [
                account_id => $acc_id,
                delete_date => undef,
            ],
        );

        while (my $client = $clients_iter->next) {
            my $sub_new_count = 0;
            my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(     # Select active subscriptions
                query => [
                    client_id => $client->id,
                    end_date => {gt => \'now()'},
                    delete_date => undef,
                ],
                sort_by => 'id'
            );
            while (my $subscr = $subscription_iter->next) {
                my $realty_count = Rplus::Model::SubscriptionRealty::Manager->get_objects_count(query => [subscription_id => $subscr->id, offered => 1]);
                next if ($subscr->realty_limit > 0 && $realty_count >= $subscr->realty_limit);      # Check realty limit

                for my $q (@{$subscr->queries}) {

                    # Skip FTS data
                    my @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } (Rplus::Util::Query::parse($q, $c));

                    if ($subscr->rent_type) {
                        push @query, rent_type => $subscr->rent_type;
                    }

                    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                        query => [
                            offer_type_code => $subscr->offer_type_code,
                            state_code => ['work'],
                            or => [
                                state_change_date => {gt => $subscr->add_date},
                                price_change_date => {gt => ($subscr->last_check_date || $subscr->add_date)},
                            ],
                            account_id => $acc_id,
                            [\"t1.id NOT IN (SELECT SR.realty_id FROM subscription_realty SR WHERE SR.subscription_id = ? AND SR.offered = TRUE)" => $subscr->id],
                            delete_date => undef,
                            @query
                        ],
                        with_objects => ['agent', 'type', 'sublandmark'],
                    );

                    while (my $realty = $realty_iter->next) {

                        my $sr = Rplus::Model::SubscriptionRealty::Manager->get_objects(query => [subscription_id => $subscr->id, realty_id => $realty->id])->[0];
                        if (!$sr) {
                          $sr = Rplus::Model::SubscriptionRealty->new(subscription_id => $subscr->id, realty_id => $realty->id);
                        }
                        $sr->offered(1);
                        $sr->save;

                        # Prepare SMS for client
                        if ($client->phone_num =~ /^9\d{9}$/) {
                            # TODO: Add template settings
                            my @parts;
                            {
                                push @parts, $realty->type->name;
                                push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                                push @parts, $realty->address if $realty->address;
                                push @parts, $realty->district if $realty->district;
                                push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
                                push @parts, $realty->price.' тыс. руб.' if $realty->price;
                                if ($subscr->client->send_owner_phone) {
                                    push @parts, "Собственник: ".join(', ', $realty->owner_phones);
                                } elsif ($realty->agent) {
                                    push @parts, "Агент: ".($realty->agent->public_name || $realty->agent->name);
                                    push @parts, $realty->agent->public_phone_num || $realty->agent->phone_num;
                                }
                            }
                            my $sms_body = join(', ', @parts);
                            my $sms_text = 'По вашему запросу поступило: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.') . ' ' . $contact_info;
                            Rplus::Model::SmsMessage->new(phone_num => $client->phone_num, text => $sms_text, account_id => $acc_id)->save;
                        }

                        # Prepare SMS for agent
                        if (!$subscr->client->send_owner_phone && $realty->agent && ($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                            # TODO: Add template settings
                            my @parts;
                            {
                                push @parts, $realty->type->name;
                                push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                                push @parts, $realty->address.($realty->district ? ' ('.$realty->district.')' : '') if $realty->address;
                                push @parts, $realty->price.' тыс. руб.' if $realty->price;
                                push @parts, 'Клиент: '.$c->format_phone_num($client->phone_num);
                            }
                            my $sms_text = 'Подобрано: '.join(', ', @parts);
                            Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text, account_id => $acc_id)->save;
                        }
                    }
                }
                $subscr->last_check_date('now()');
                $subscr->save(chages_only => 1);
            }
        }
    }
    return;
}

1;
