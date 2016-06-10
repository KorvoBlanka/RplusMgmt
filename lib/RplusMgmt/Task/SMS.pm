package RplusMgmt::Task::SMS;

use Rplus::Modern;

use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Mojo::UserAgent;
use JSON;


sub run {
    my $c = shift;


    my $stop = 0;
    my $account_iter = Rplus::Model::Account::Manager->get_objects_iterator(query => [del_date => undef]);
    while (my $account = $account_iter->next) {

        my $acc_id = $account->id;
        my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
        my $config;
        if ($options) {
            $config = from_json($options->{options})->{'notifications'};
        }

        if ($config->{active} ne '1' && $config->{active} ne 'true') {
            next;
        }

        my $sm_iter = Rplus::Model::SmsMessage::Manager->get_objects_iterator(query => [status => 'queued', account_id => $acc_id,], sort_by => 'id');
        $stop = 0;
        while ((my $sm = $sm_iter->next) && !$stop) {
            $sm->attempts_count($sm->attempts_count + 1);

            $c->app->log->debug(sprintf("Sending SMS: (%s) %s => %s", $sm->id, $sm->phone_num, $sm->text));

            my $ua = Mojo::UserAgent->new;
            my $tx = $ua->post('https://smsc.ru/sys/send.php' => form => {
                login => $config->{login},
                psw => $config->{password},
                ($config->{tz} ? (tz => $config->{tz}) : ()),
                ($config->{company} ? (sender => $config->{company}) : ()),
                phones => '+7'.$sm->phone_num,
                mes => $sm->text,
                id => $sm->id,
                charset => 'utf-8',
                cost => 2,
                fmt => 3,
            });
            if (my $res  = $tx->success) {
                if (my $x = $res->json) {
                    if ($x->{'error_code'}) {
                        $sm->status('error');
                        $sm->last_error_msg(sprintf("(%s) %s", $x->{'error_code'}, $x->{'error'}));
                        if ($x->{'error_code'} == 2 || $x->{'error_code'} == 3 || $x->{'error_code'} == 4) {
                            $stop = 1;
                        }
                    } else {
                        $sm->status('sent');
                    }
                } else {
                    $sm->status('error');
                    $sm->last_error_msg("Cannot parse a response as json");
                    $stop = 1;
                }
            } else {
                my ($err, $code) = $tx->error;
                $sm->status('error');
                $sm->last_error_msg($code ? "$code response: $err" : "Connection error: $err");
            }

            $sm->save;
        }
    }
    return;
}

1;
