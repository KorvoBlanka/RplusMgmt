package RplusMgmt::Task::CalendarSync;

use Rplus::Modern;

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Util::GoogleCalendar;

sub run {
    my $c = shift;
    my $account_iter = Rplus::Model::Account::Manager->get_objects_iterator(query => [del_date => undef]);
    while (my $account = $account_iter->next) {
        Rplus::Util::GoogleCalendar::syncAll($account->id);
    }

    return;
}

1;
