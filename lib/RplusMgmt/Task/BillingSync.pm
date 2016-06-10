package RplusMgmt::Task::BillingSync;

use Rplus::Modern;

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;


my $ua = Mojo::UserAgent->new;

sub run {
    my $c = shift;

    my $account_iter = Rplus::Model::Account::Manager->get_objects_iterator(query => [del_date => undef]);
    while (my $account = $account_iter->next) {
    #    Rplus::Util::Billing::syncAll($account->id);

      my $tx = $ua->get('http://rplusmgmt.com/api/account/get_by_name?name=' . $account->name);
      if (my $res = $tx->success) {
          if ($res->json->{'status'} eq 'ok') {
              my $acc_data = $res->json->{'data'};

              $account->balance($acc_data->{balance});
              $account->user_count($acc_data->{user_count});
              $account->mode($acc_data->{mode});
              $account->location_id($acc_data->{location_id});

              $account->save();
          }
      }

    }

    return;
}

1;
