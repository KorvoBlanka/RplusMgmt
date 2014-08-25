package Rplus::Util::Email;

use Rplus::Modern;

use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use MIME::Lite;
use IPC::Open2;
use JSON;

sub send {
    my ($class, $self, $email, $message_text, $config) = @_;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'notifications')->load();
    my $config;
    if ($rt_param) {
        $config = from_json($rt_param->{value});
    } else {
        return;
    }

    $self->app->log->debug(sprintf("Sending email: (%s) %s => %s", -1, $email, $message_text));
    send_email($email, 'Подобрана недвижимость', $message_text, $config);

    return 'success';
}

sub send_email {
    my ($to, $subject, $message, $config) = @_;

    my $from = 'info@rplusmgmt.com';

    my $msg = MIME::Lite->new(
                   From     => $from,
                   To       => $to,
                   Subject  => $subject,
                   Data     => $message
                   );

    $msg->attr("content-type" => "text/html; charset=UTF-8");

    my $port = 587;
    if ($config->{'email-port'} =~ /^(\d+)$/) {
      $port = $1;
    }
    $msg->send('smtp', $config->{'email-smtp'}, AuthUser => $config->{'email-user'}, AuthPass => $config->{'email-password'}, Port => $port);
}

1;
