package Rplus::Util::SMS;

use Rplus::Modern;

use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Mojo::UserAgent;
use JSON;

sub send {
    my ($class, $self, $phone_num, $message_text, $config) = @_;

    return unless $config->{active};


    my $sms = Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $message_text)->save;

    $self->app->log->debug(sprintf("Sending SMS: (%s) %s => %s", -1, $phone_num, $message_text));

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->post('https://smsc.ru/sys/send.php' => form => {
        login => $config->{login},
        psw => $config->{password},
        ($config->{tz} ? (tz => $config->{tz}) : ()),
        ($config->{company} ? (sender => $config->{company}) : ()),
        phones => '+7'.$phone_num,
        mes => $message_text,
        id => $sms->id,
        charset => 'utf-8',
        cost => 2,
        fmt => 3,
    });
    if (my $res  = $tx->success) {
        if (my $x = $res->json) {
            if ($x->{'error_code'}) {
                $sms->status('error');
                $sms->last_error_msg(sprintf("(%s) %s", $x->{'error_code'}, $x->{'error'}));
            } else {
                $sms->status('sent');
            }
        } else {
            $sms->status('error');
            $sms->last_error_msg("Cannot parse a response as json");
        }
    } else {
        my ($err, $code) = $tx->error;
        $sms->status('error');
        $sms->last_error_msg($code ? "$code response: $err" : "Connection error: $err");
    }

    $sms->save;

    return 'success';
}

1;
