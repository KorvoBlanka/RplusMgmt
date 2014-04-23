package RplusMgmt::Task::Subscriptions;

use Rplus::Modern;

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Rplus::Util::Query;

sub run {
    my $class = shift;
    my $c = shift;

    # Select active subscriptions
    my $subscr_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(query => [end_date => {gt => \'now()'}, delete_date => undef], with_objects => ['client'], sort_by => 'id');
    while (my $subscr = $subscr_iter->next) {
        $c->app->log->debug("Processing subscription #".$subscr->id);

        # Check realty limit
        my $realty_count = Rplus::Model::SubscriptionRealty::Manager->get_objects_count(query => [subscription_id => $subscr->id, delete_date => undef]);
        if ($subscr->realty_limit > 0 && $realty_count >= $subscr->realty_limit) {
            $c->app->log->debug("Skipping. Subscription realty limit is exceeded.");
            next;
        }

        for my $q (@{$subscr->queries}) {
            $c->app->log->debug("Query: $q");

            # Skip FTS data
            my @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } (Rplus::Util::Query->parse($q));

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    offer_type_code => $subscr->offer_type_code,
                    state_code => 'work',
                    or => [
                        state_change_date => {gt => $subscr->add_date},
                        price_change_date => {gt => ($subscr->last_check_date || $subscr->add_date)},
                    ],
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

                    # Prepare SMS for client
                    if ($subscr->client->phone_num =~ /^9\d{9}$/) {
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
                        my $sms_text = 'По вашему запросу поступило: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').($c->config->{subscriptions}->{contact_info} ? ' '.$c->config->{subscriptions}->{contact_info} : '');
                        Rplus::Model::SmsMessage->new(phone_num => $subscr->client->phone_num, text => $sms_text)->save;
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
                            push @parts, 'Клиент: '.$c->format_phone_num($subscr->client->phone_num);
                        }
                        my $sms_text = 'Подобрано: '.join(', ', @parts);
                        Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text)->save;
                    }
            }
            $c->app->log->debug("Found: $found");
        }

        $subscr->last_check_date('now()');
        $subscr->save(chages_only => 1);
    }

    return;
}

1;
