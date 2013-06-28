package TAEB::AI::Magus::Goal::KillShopkeepers;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'GetCrowned' }

1;

