package RplusMgmt::Task::Subscriptions;

use Rplus::Modern;

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
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Rplus::Util::Query;
use JSON;

sub run {
    my $class = shift;
    my $c = shift;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'notifications')->load();
    my $contact_info = '';
    if ($rt_param) {
        my $config = from_json($rt_param->{value});
        $contact_info = $config->{'contact_info'} ? $config->{'contact_info'} : '';
    }


    my $clients_iter = Rplus::Model::Client::Manager->get_objects_iterator(
        query => [
            delete_date => undef,
        ],
    );

    while (my $client = $clients_iter->next) {
        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(     # Select active subscriptions
            query => [
                client_id => $client->id,
                end_date => {gt => \'now()'},
                delete_date => undef,
            ],
            sort_by => 'id'
        );
        my $sub_new_count = 0;
        while (my $subscr = $subscription_iter->next) {
            my $realty_count = Rplus::Model::SubscriptionRealty::Manager->get_objects_count(query => [subscription_id => $subscr->id, state_code => 'offered', delete_date => undef]);
            next if ($subscr->realty_limit > 0 && $realty_count >= $subscr->realty_limit);      # Check realty limit

            for my $q (@{$subscr->queries}) {

                # Skip FTS data
                my @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } (Rplus::Util::Query->parse($q, $c));

                my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $subscr->offer_type_code,
                        state_code => ['work', 'raw'],
                        or => [
                            state_change_date => {gt => $subscr->add_date},
                            price_change_date => {gt => ($subscr->last_check_date || $subscr->add_date)},
                        ],
                        [\"t1.id NOT IN (SELECT SR.realty_id FROM subscription_realty SR WHERE SR.subscription_id = ? AND SR.state_code = 'offered' AND SR.delete_date IS NULL)" => $subscr->id],
                        delete_date => undef,
                        @query
                    ],
                    with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
                );
                my $found = 0;
                while (my $realty = $realty_iter->next) {
                    $found++;
                    next if $realty->state_code ne 'work';

                    my $sr = Rplus::Model::SubscriptionRealty::Manager->get_objects(query => [subscription_id => $subscr->id, realty_id => $realty->id])->[0];
                    if (!$sr) {
                      $sr = Rplus::Model::SubscriptionRealty->new(subscription_id => $subscr->id, realty_id => $realty->id);
                    }
                    $sr->state_code('offered');
                    $sr->save;

                    # Prepare SMS for client
                    if ($client->phone_num =~ /^9\d{9}$/) {
                        # TODO: Add template settings
                        my @parts;
                        {
                            push @parts, $realty->type->name;
                            push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                            push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->address_object->name !~ /[()]/ && $realty->sublandmark ? ' ('.$realty->sublandmark->name.')' : '') if $realty->address_object;
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
                        Rplus::Model::SmsMessage->new(phone_num => $client->phone_num, text => $sms_text)->save;
                    }

                    # Prepare SMS for agent
                    if (!$subscr->client->send_owner_phone && $realty->agent && ($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                        # TODO: Add template settings
                        my @parts;
                        {
                            push @parts, $realty->type->name;
                            push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                            push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                            push @parts, $realty->price.' тыс. руб.' if $realty->price;
                            push @parts, 'Клиент: '.$c->format_phone_num($client->phone_num);
                        }
                        my $sms_text = 'Подобрано: '.join(', ', @parts);
                        Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text)->save;
                    }
                }
                if ($found > 0) {
                    $sub_new_count ++;
                }
            }
            $subscr->last_check_date('now()');
            $subscr->save(chages_only => 1);
        }
        $client->metadata(encode_json({subscription_with_new_realty => $sub_new_count}));
        $client->save(chages_only => 1);
    }

    return;
}

1;
