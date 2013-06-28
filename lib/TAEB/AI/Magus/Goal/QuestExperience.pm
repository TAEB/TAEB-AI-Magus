package TAEB::AI::Magus::Goal::QuestExperience;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->level >= 14 }

1;

