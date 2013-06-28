package TAEB::AI::Magus::Goal::CastleSmash;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'FindTune' }

1;

