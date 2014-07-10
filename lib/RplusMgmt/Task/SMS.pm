package RplusMgmt::Task::SMS;

use Rplus::Modern;

use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Mojo::UserAgent;
use JSON;

sub run {
    my $class = shift;
    my $c = shift;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'notifications')->load();
    my $config;
    if ($rt_param) {
        $config = from_json($rt_param->{value});
    } else {
        return;
    }

    return unless $config->{active};

    my $sm_iter = Rplus::Model::SmsMessage::Manager->get_objects_iterator(query => [status => 'queued'], sort_by => 'id');
    while (my $sm = $sm_iter->next) {
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
                } else {
                    $sm->status('sent');
                }
            } else {
                $sm->status('error');
                $sm->last_error_msg("Cannot parse a response as json");
            }
        } else {
            my ($err, $code) = $tx->error;
            $sm->status('error');
            $sm->last_error_msg($code ? "$code response: $err" : "Connection error: $err");
        }

        $sm->save;
    }

    return;
}

1;
