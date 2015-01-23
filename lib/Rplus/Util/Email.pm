package Rplus::Util::Email;

use Rplus::Modern;

use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use MIME::Lite;
use IPC::Open2;
use JSON;
use Net::SMTP::SSL;

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

sub send_email_old {
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

sub send_email {
    my ($to, $subject, $message, $config) = @_;

    my $from = $config->{'email-user'};
  
    my $msg = MIME::Lite->new(
                   From     => $from,
                   To       => $to,
                   Subject  => $subject,
                   Data     => $message
                   );               
    $msg->attr("content-type" => "text/html; charset=UTF-8");     
    #$msg->send('smtp', 'smtp.yandex.ru', AuthUser=>'info@rplusmgmt.com', AuthPass=>'ckj;ysqgfhjkm', Port => 587);

    my $port = 465;
    if ($config->{'email-port'} =~ /^(\d+)$/) {
      $port = $1;
    }

    my $smtp = Net::SMTP::SSL->new($config->{'email-smtp'}, Port => $port); # or die "Can't connect";
    $smtp->auth($config->{'email-user'}, $config->{'email-password'}); # or die "Can't authenticate:".$smtp->message();
    $smtp->mail($config->{'email-user'}); # or die "Error:".$smtp->message();
    $smtp->to($to); # or die "Error:".$smtp->message();
    $smtp->data(); # or die "Error:".$smtp->message();
    $smtp->datasend($msg->as_string); # or die "Error:".$smtp->message();
    $smtp->dataend(); # or die "Error:".$smtp->message();
    $smtp->quit(); # or die "Error:".$smtp->message();

}

1;
