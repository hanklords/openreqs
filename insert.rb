require 'mongo'

DB = Mongo::Connection.new.db("openreqs")
docs, reqs = DB["docs"], DB["requirements"]


doc = {
  'content' => %q{= Requirements Engineering Tool User needs
      
Last Modified on 14th of September 2011.
      
This document aims at specifying "Requirements Engineering Tool" user needs
      
= Functional aspects
      
[[OpenReq-UN-001.req]]
}
  }
docs.insert(doc)

req = {
  'rationale' => "To take over the world",
  'date' => "2011-09-14",
  'content' => %q{OpenReq shall replace Doors(c)}
  }

reqs.insert(req)
