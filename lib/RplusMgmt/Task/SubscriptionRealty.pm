package RplusMgmt::Task::SubscriptionRealty;

use Rplus::Modern;

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;

use Rplus::Util::Query;
use JSON;

sub run {
    my $class = shift;
    my $c = shift;

    my $clients_iter = Rplus::Model::Client::Manager->get_objects_iterator(
        query => [
            delete_date => undef,
        ],
        limit => 99,
    );

    while (my $client = $clients_iter->next) {
        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(
            query => [
                client_id => $client->id,
                delete_date => undef,
                #end_date => {gt => \'now()'},
            ],
        );
        my $sub_new_count = 0;
        while (my $subscription = $subscription_iter->next) {
            realty_update($c, $subscription->id);
        }
    }


    return;
}

sub realty_update {
    my ($self, $subscription_id) = @_;
    my $subscription = Rplus::Model::Subscription::Manager->get_objects(query => [id => $subscription_id, delete_date => undef])->[0];

    for my $q (@{$subscription->queries}) {
        # Skip FTS data
        my @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } (Rplus::Util::Query->parse($q, $self));

        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [
                offer_type_code => $subscription->offer_type_code,
                or => [
                  state_code => 'work',
                  state_code => 'suspended',
                  state_code => 'raw',
                ],
                #or => [
                #    state_change_date => {gt => $subscription->add_date},
                #    price_change_date => {gt => ($subscription->last_check_date || $subscription->add_date)},
                #],
                [\"t1.id NOT IN (SELECT SR.realty_id FROM subscription_realty SR WHERE SR.subscription_id = ? AND SR.delete_date IS NULL)" => $subscription->id],
                delete_date => undef,
                @query
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

1;
