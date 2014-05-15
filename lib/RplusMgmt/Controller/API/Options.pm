package RplusMgmt::Controller::API::Options;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use JSON;

sub list {
    my $self = shift;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'opt_var')->load();
    my $val = {};
    if (!$rt_param) {
        Rplus::Model::RuntimeParam->new(key => 'opt_var', value => "{}")->save; # Create record
    } else {
        $val = from_json($rt_param->{value});
    }

    my $res = {
        val => $val,
    };

    return $self->render(json => $res);    
}

sub listexp {
    my $self = shift;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'exp_var')->load();
    my $val = {};
    if (!$rt_param) {
        Rplus::Model::RuntimeParam->new(key => 'exp_var', value => "{}")->save; # Create record
    } else {
        $val = from_json($rt_param->{value});
    }

    my $res = {
        val => $val,
    };

    return $self->render(json => $res);    
}

sub listnot {
    my $self = shift;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'not_var')->load();
    my $val = {};
    if (!$rt_param) {
        Rplus::Model::RuntimeParam->new(key => 'not_var', value => "{}")->save; # Create record
    } else {
        $val = from_json($rt_param->{value});
    }
    
    my $res = {
        val => $val,
    };

    return $self->render(json => $res);    
}

sub get {
    my $self = shift;

    my $name = $self->param('name');

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'opt_var')->load();
    my $val = 0;
    if (!$rt_param) {
        Rplus::Model::RuntimeParam->new(key => 'tasks_run_mutex', value => "{\"$name\": 0}")->save; # Create record
    } else {
        $val = from_json($rt_param->{value})->{$name};
    }
    
    my $res = {
        name => $name,
        val => $val,
    };

    return $self->render(json => $res);
}

sub set {
    my $self = shift;

    my $name = $self->param('name');
    my $val = $self->param_b('value');

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'opt_var')->load();
    
    my $vals = from_json($rt_param->{value});
    $vals->{$name} = $val;
    $rt_param->value(encode_json($vals));
    $rt_param->save;
    
    return $self->render(json => {status => 'success'});
}

sub setexp {
    my $self = shift;

    my $name = $self->param('name');
    my $val = $self->param('value');

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'exp_var')->load();
    
    my $vals = from_json($rt_param->{value});
    $vals->{$name} = $val;
    $rt_param->value(encode_json($vals));
    $rt_param->save;
    
    return $self->render(json => {status => 'success'});
}

sub setnot {
    my $self = shift;

    my $name = $self->param('name');
    my $val = $self->param('value');

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'not_var')->load();
    
    my $vals = from_json($rt_param->{value});
    $vals->{$name} = $val;
    $rt_param->value(encode_json($vals));
    $rt_param->save;
    
    return $self->render(json => {status => 'success'});
}

1;
